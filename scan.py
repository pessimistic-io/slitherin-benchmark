import aiohttp
import asyncio
from config import API_ENDPOINT_BY_CHAIN, API_KEY_BY_CHAIN

async def get_raw_source(address:str, chain_id:str, retry:int = 3):
    """Function download contract from etherscan(or other chain scan)

    Args:
        address: Contract address.
        chain_id: hex chain id.

    Returns:
        Etherscan API query result
    """
    url = f"{API_ENDPOINT_BY_CHAIN[chain_id]}&address={address}&apikey={API_KEY_BY_CHAIN[chain_id]}"

    try:
        async with aiohttp.ClientSession() as session:
            async with session.get(url) as resp:
                if resp.status == 200:
                    resp_json = await resp.json()
                    if "result" in resp_json and len(resp_json["result"]) > 0:
                        if isinstance(resp_json["result"], list):
                            return resp_json["result"][0]
                else:
                    print(f"retry status {resp.status}")
                    await asyncio.sleep(5)
                    if retry > 0:
                        return await get_raw_source(address, chain_id, retry-1) 
        return None
    except Exception as error:
        print(error)
        return None

if __name__ == "__main__":
    tasks = []
    tasks.append(get_raw_source("0x1F42800E8fa0F87443B4BBFf590C89cB3DE73042", "0x1"))
    tasks.append(get_raw_source("0x24Ec19F05Fc4a29d49617e1221cE7dC8A1ed5A3d", "0x1"))
    import asyncio
    fut = asyncio.gather(*tasks, return_exceptions=True)
    loop = asyncio.get_event_loop()
    print("run %d tasks" % len(tasks))
    responses = loop.run_until_complete(fut)
    print("completed")
    for response in responses:
        print(response)
        print("--------------")
