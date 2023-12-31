// SPDX-License-Identifier: GPL-3.0-only

pragma solidity >=0.8.15;

import "./SafeERC20.sol";
import "./IERC20.sol";
import "./Ownable.sol";

import "./IBridgeAdapter.sol";
import "./ISpokePool.sol";

contract AcrossAdapter is IBridgeAdapter, Ownable {
    using SafeERC20 for IERC20;

    address public spokePool;

    event SpokePoolUpdated(address spokePool);

    constructor(address _spokePool) {
        spokePool = _spokePool;
    }

    struct BridgeParams {
        uint64 relayerFeePct;
        uint32 quoteTimestamp;
    }

    function bridge(
        uint64 _dstChainId,
        address _receiver,
        uint256 _amount,
        address _token,
        bytes memory _bridgeParams,
        bytes memory //_requestMessage
    ) external payable returns (bytes memory bridgeResp) {
        BridgeParams memory params = abi.decode(_bridgeParams, (BridgeParams));
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        ISpokePool(spokePool).deposit(
            _receiver,
            _token,
            _amount,
            _dstChainId,
            params.relayerFeePct,
            params.quoteTimestamp
        );
        uint32 depositId = ISpokePool(spokePool).numberOfDeposits();
        return abi.encode(depositId);
    }

    function setSpokePool(address _spokePool) external onlyOwner {
        spokePool = _spokePool;
        emit SpokePoolUpdated(_spokePool);
    }

    // convenience function to make encoding bridge params easier using ABI generated go code
    function encodeBridgeParams(BridgeParams memory _params) external {}
}

