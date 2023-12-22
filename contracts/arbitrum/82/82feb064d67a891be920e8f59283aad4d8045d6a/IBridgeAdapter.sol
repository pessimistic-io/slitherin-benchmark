pragma solidity >0.8.0;

import "./IERC20.sol";

interface IBridgeAdapter {
    function sendAssets(
        uint256 value,
        address to,
        uint8 slippage
    ) external returns (bytes32 transferId);
}

