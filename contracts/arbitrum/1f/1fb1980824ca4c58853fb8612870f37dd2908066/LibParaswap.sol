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

error ParaswapError(bytes _data);
error UnknownParaswapError();

library LibParaswap {
    using SafeERC20 for IERC20;

    bytes32 constant PARASWAP_STORAGE_POSITION = keccak256("paraswap.portal.strateg.io");

    event ParaswapExecutionResult(bool success, bytes returnData);

    struct ParaswapConfig {
        address augustus;
    }

    struct ParaswapStorage {
        ParaswapConfig config;
        
    }

    function paraswapStorage() internal pure returns (ParaswapStorage storage ds) {
        bytes32 position = PARASWAP_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }

    function setAugustus(address _augustus) internal {
        ParaswapStorage storage store = paraswapStorage();
        store.config.augustus = _augustus;
    }

    function getAugustus() internal view returns (address) {
        return paraswapStorage().config.augustus;
    }

    function execute(address _sourceAsset, address _approvalAddress, uint256 _amount, bytes calldata _data) internal {
        ParaswapStorage storage store = paraswapStorage();
        address augustus = store.config.augustus;
        IERC20(_sourceAsset).safeApprove(_approvalAddress, _amount);
        
        (bool success, bytes memory returnData) = augustus.call{value: msg.value}(_data);
        if (!success) {
            if (returnData.length == 0) revert UnknownParaswapError();
            assembly {
                revert(add(32, returnData), mload(returnData))
            }
        }

        IERC20(_sourceAsset).safeApprove(augustus, 0);
        emit ParaswapExecutionResult(success, returnData);
    }

}

