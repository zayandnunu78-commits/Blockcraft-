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

#include "HttpDownload.h"

#include <cstdint>
#include <cstdio>
#include <fstream>
#include <roapi.h>
#include <vector>

#include <winrt/Windows.Foundation.h>
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

} // namespace

bool httpDownload(const char *url, const char *path, const char *userAgent, const char *accept)
{
	if (!url || !url[0] || !path || !path[0])
		return false;

	Apartment apartment;
	if (!apartment.ready())
		return false;

	bool opened = false;
	try
	{
		namespace Http = winrt::Windows::Web::Http;
		namespace Streams = winrt::Windows::Storage::Streams;

		Http::HttpClient client;
		Http::HttpRequestMessage request(Http::HttpMethod::Get(),
			winrt::Windows::Foundation::Uri(winrt::to_hstring(url)));
		if (userAgent && userAgent[0])
			request.Headers().TryAppendWithoutValidation(L"User-Agent", winrt::to_hstring(userAgent));
		if (accept && accept[0])
			request.Headers().TryAppendWithoutValidation(L"Accept", winrt::to_hstring(accept));

		auto response = client.SendRequestAsync(request,
			Http::HttpCompletionOption::ResponseHeadersRead).get();
		if (!response.IsSuccessStatusCode())
			return false;

		std::ofstream output(path, std::ios::binary | std::ios::trunc);
		if (!output)
			return false;
		opened = true;

		auto stream = response.Content().ReadAsInputStreamAsync().get();
		Streams::DataReader reader(stream);
		while (true)
		{
			uint32_t count = reader.LoadAsync(64 * 1024).get();
			if (count == 0)
				break;
			std::vector<uint8_t> bytes(count);
			reader.ReadBytes(bytes);
			output.write(reinterpret_cast<const char *>(bytes.data()), bytes.size());
			if (!output)
				throw std::ios_base::failure("download write failed");
		}

		output.close();
		if (!output)
			throw std::ios_base::failure("download close failed");
		return true;
	}
	catch (...)
	{
		if (opened)
			std::remove(path);
		return false;
	}
}

} // uwp
} // system
} // love
