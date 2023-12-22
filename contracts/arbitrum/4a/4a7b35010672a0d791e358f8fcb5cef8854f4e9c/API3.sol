// SPDX-License-Identifier: MIT
import "./interfaces_IProxy.sol";

contract DataFeedReader {
    // The proxy contract address obtained from the API3 Market UI.
    function readDataFeed(address proxyAddress)
        external
        view
        returns (int224 value, uint256 timestamp)
    {
        // Use the IProxy interface to read a dAPI via its
        // proxy contract .
        (value, timestamp) = IProxy(proxyAddress).read();
        // If you have any assumptions about `value` and `timestamp`,
        // make sure to validate them after reading from the proxy.
    }

}
