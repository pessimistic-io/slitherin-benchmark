// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/******************************************************************************\
* Author: Nick Mudge <nick@perfectabstractions.com> (https://twitter.com/mudgen)
* EIP-2535 Diamonds: https://eips.ethereum.org/EIPS/eip-2535
/******************************************************************************/
import { IDiamondCut } from "./interfaces_IDiamondCut.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./console.sol";
// Remember to add the loupe functions from DiamondLoupeFacet to the diamond.
// The loupe functions are required by the EIP2535 Diamonds standard

error OneInchError(bytes _data);
error UnknownOneInchError();

library LibOneInch {
    using SafeERC20 for IERC20;

    bytes32 constant ONEINCH_STORAGE_POSITION = keccak256("1inch.portal.strateg.io");

    event OneInchExecutionResult(bool success, bytes returnData);

    struct OneInchConfig {
        address router;
    }

    struct OneInchStorage {
        OneInchConfig config;
        
    }

    function oneInchStorage() internal pure returns (OneInchStorage storage ds) {
        bytes32 position = ONEINCH_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }

    function setRouter(address _router) internal {
        OneInchStorage storage store = oneInchStorage();
        store.config.router = _router;
    }

    function getRouter() internal view returns (address) {
        return oneInchStorage().config.router;
    }

    function execute(address _sourceAsset, address _approvalAddress, uint256 _amount, bytes calldata _data) internal {
        OneInchStorage storage store = oneInchStorage();
        address router = store.config.router;
        IERC20(_sourceAsset).safeApprove(_approvalAddress, _amount);
        
        (bool success, bytes memory returnData) = router.call{value: msg.value}(_data);
        if (!success) {
            if (returnData.length == 0) revert UnknownOneInchError();
            assembly {
                revert(add(32, returnData), mload(returnData))
            }
        }

        IERC20(_sourceAsset).safeApprove(router, 0);
        emit OneInchExecutionResult(success, returnData);
    }

}

