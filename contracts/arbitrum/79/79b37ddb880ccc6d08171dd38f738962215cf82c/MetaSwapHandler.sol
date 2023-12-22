// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.18;

import { CoreSwapHandlerV1 } from "./CoreSwapHandlerV1.sol";
import { IMetaSwapHandler } from "./IMetaSwapHandler.sol";
import { SwapDeadlineExceeded, InvalidDestinationSwapper } from "./DefinitiveErrors.sol";
import { Ownable } from "./Ownable.sol";
import { Address } from "./Address.sol";

/**
 * @title MetaSwapHandler
 * @author WardenJakx
 * @notice Meta swap handler to swap anywhere
 */
contract MetaSwapHandler is CoreSwapHandlerV1, IMetaSwapHandler, Ownable {
    receive() external payable {}

    mapping(address => bool) public whitelistedSwapContracts;

    /**
     * @param owner we may not be using msgSender() so an owner address is specified to be the owner
     * @param whitelistedContracts DEX routers to whitelist (eg 0x router)m
     */
    constructor(address owner, address[] memory whitelistedContracts) payable {
        transferOwnership(owner);
        _updateWhitelist(whitelistedContracts, true);
    }

    function removeFromWhitelist(address[] calldata contracts) external onlyOwner {
        _updateWhitelist(contracts, false);
    }

    function addToWhitelist(address[] calldata contracts) external onlyOwner {
        _updateWhitelist(contracts, true);
    }

    function _performSwap(SwapParams memory params) internal override {
        MetaSwapParams memory swapParams = abi.decode(params.data, (MetaSwapParams));
        Address.functionCallWithValue(swapParams.underlyingSwapRouterAddress, swapParams.swapData, msg.value);
    }

    function _getSpenderAddress(bytes memory data) internal pure override returns (address) {
        MetaSwapParams memory swapParams = abi.decode(data, (MetaSwapParams));
        return swapParams.underlyingSwapRouterAddress;
    }

    function _validatePools(SwapParams memory, bool) internal view override {}

    function _validateSwap(SwapParams memory params) internal view override {
        MetaSwapParams memory swapParams = abi.decode(params.data, (MetaSwapParams));

        if (!whitelistedSwapContracts[swapParams.underlyingSwapRouterAddress]) {
            revert InvalidDestinationSwapper();
        }

        if (swapParams.deadline < block.timestamp) {
            revert SwapDeadlineExceeded();
        }
    }

    function _updateWhitelist(address[] memory contracts, bool isWhitelisted) private {
        uint256 contractsLength = contracts.length;
        for (uint256 i; i < contractsLength; ) {
            whitelistedSwapContracts[contracts[i]] = isWhitelisted;

            unchecked {
                ++i;
            }
        }
    }
}

