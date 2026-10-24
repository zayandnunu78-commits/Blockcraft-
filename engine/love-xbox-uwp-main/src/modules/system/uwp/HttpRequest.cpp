/**
 * Copyright (c) 2006-2023 LOVE Development Team
 *
 * This software is provided 'as-is', without any express or implied
 * warranty.  In no event will the authors be held liable for any damages
 * arising from the use of this software.
 *
 * Permission is granted to anyone to use this software for any purpose,
 * including commercial applications, and to alter it and redistribute it
 * freely, subject to the following restrictions:
 *
 * 1. The origin of this software must not be misrepresented; you must not
 *    claim that you wrote the original software. If you use this software
 *    in a product, an acknowledgment in the product documentation would be
 *    appreciated but is not required.
 * 2. Altered source versions must be plainly marked as such, and must not be
 *    misrepresented as being the original software.
 * 3. This notice may not be removed or altered from any source distribution.
 **/

#include "HttpRequest.h"

#include <cctype>
#include <roapi.h>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Storage.Streams.h>
#include <winrt/Windows.Web.Http.h>
#include <winrt/Windows.Web.Http.Headers.h>

namespace love
{
namespace system
{
namespace uwp
{

namespace
{

class Apartment
{
public:
	Apartment()
		: result(RoInitialize(RO_INIT_MULTITHREADED))
	{}

	~Apartment()
	{
		if (SUCCEEDED(result))
			RoUninitialize();
	}

	bool ready() const
	{
		return SUCCEEDED(result);
	}

private:
	HRESULT result;
};

bool equalsIgnoreCase(const std::string &left, const char *right)
{
	size_t i = 0;
	for (; i < left.size() && right[i]; i++)
	{
		if (std::tolower((unsigned char) left[i]) != std::tolower((unsigned char) right[i]))
			return false;
	}
	return i == left.size() && right[i] == '\0';
}

bool startsWithIgnoreCase(const std::string &value, const char *prefix)
{
	for (size_t i = 0; prefix[i]; i++)
	{
		if (i >= value.size()
			|| std::tolower((unsigned char) value[i]) != std::tolower((unsigned char) prefix[i]))
			return false;
	}
	return true;
}

std::string errorEnvelope(std::string message)
{
	for (char &c : message)
	{
		if (c == '\r' || c == '\n')
			c = ' ';
	}
	if (message.empty())
		message = "request failed";
	return "ERROR " + message;
}

} // namespace

std::string httpRequest(const std::string &url, const std::string &method,
	const std::vector<HttpHeader> &headers, const std::string *body,
	const std::string &userAgent)
{
	if (url.empty() || method.empty())
		return errorEnvelope("missing URL or method");

	Apartment apartment;
	if (!apartment.ready())
		return errorEnvelope("could not initialize Windows Runtime");

	try
	{
		namespace Http = winrt::Windows::Web::Http;
		namespace Streams = winrt::Windows::Storage::Streams;

		Http::HttpClient client;
		Http::HttpRequestMessage request(Http::HttpMethod(winrt::to_hstring(method)),
			winrt::Windows::Foundation::Uri(winrt::to_hstring(url)));
		Http::IHttpContent content = nullptr;
		if (body)
		{
			content = Http::HttpStringContent(winrt::to_hstring(*body),
				Streams::UnicodeEncoding::Utf8);
			request.Content(content);
		}

		bool haveUserAgent = false;
		for (const HttpHeader &header : headers)
		{
			if (header.first.empty() || header.first.find_first_of("\r\n") != std::string::npos
				|| header.second.find_first_of("\r\n") != std::string::npos)
				return errorEnvelope("bad request header");

			if (equalsIgnoreCase(header.first, "User-Agent"))
				haveUserAgent = true;

			if (startsWithIgnoreCase(header.first, "Content-"))
			{
				if (!content)
				{
					content = Http::HttpStringContent(L"", Streams::UnicodeEncoding::Utf8);
					request.Content(content);
				}
				if (equalsIgnoreCase(header.first, "Content-Type"))
					content.Headers().Remove(L"Content-Type");
				if (!content.Headers().TryAppendWithoutValidation(
					winrt::to_hstring(header.first), winrt::to_hstring(header.second)))
					return errorEnvelope("bad request header");
			}
			else if (!request.Headers().TryAppendWithoutValidation(
				winrt::to_hstring(header.first), winrt::to_hstring(header.second)))
				return errorEnvelope("bad request header");
		}

		if (!haveUserAgent && !userAgent.empty()
			&& !request.Headers().TryAppendWithoutValidation(L"User-Agent",
				winrt::to_hstring(userAgent)))
			return errorEnvelope("bad user agent");

		auto response = client.SendRequestAsync(request).get();
		std::string responseBody = winrt::to_string(
			response.Content().ReadAsStringAsync().get());
		unsigned int status = static_cast<unsigned int>(response.StatusCode());
		return "STATUS " + std::to_string(status) + "\n" + responseBody;
	}
	catch (const winrt::hresult_error &e)
	{
		return errorEnvelope(winrt::to_string(e.message()));
	}
	catch (const std::exception &e)
	{
		return errorEnvelope(e.what());
	}
	catch (...)
	{
		return errorEnvelope("request failed");
	}
}

} // uwp
} // system
} // love
