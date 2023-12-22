// SPDX-License-Identifier: GPL-3.0

// import "forge-std/console.sol";

import "./GmxLeveragePositionDataDecoder.sol";
import "./IGmxLeveragePosition.sol";
import "./IValueInterpreterGmxLeveragePosition.sol";
import "./IExternalPositionParserGmxLeveragePosition.sol";

pragma solidity 0.7.6;

/// @title GmxLeveragePositionParser
/// @author Alfred Team <alfred.capital>
/// @notice Parser for Gmx leverage Positions
contract GmxLeveragePositionParser is
    GmxLeveragePositionDataDecoder,
    IExternalPositionParserGmxLeveragePosition
{
    address private immutable WETH_TOKEN;
    address private immutable VALUE_INTERPRETER;

    constructor(address _valueInterpreter, address _weth) public {
        WETH_TOKEN = _weth;
        VALUE_INTERPRETER = _valueInterpreter;
    }

    /// @notice Parses the assets to send and receive for the callOnExternalPosition
    /// @param _externalPosition The _externalPosition to be called
    /// @param _actionId The _actionId for the callOnExternalPosition
    /// @param _encodedActionArgs The encoded parameters for the callOnExternalPosition
    /// @return assetsToTransfer_ The assets to be transferred from the Vault
    /// @return amountsToTransfer_ The amounts to be transferred from the Vault
    /// @return assetsToReceive_ The assets to be received at the Vault
    function parseAssetsForAction(
        address _externalPosition,
        uint256 _actionId,
        bytes memory _encodedActionArgs
    )
        external
        view
        override
        returns (
            address[] memory assetsToTransfer_,
            uint256[] memory amountsToTransfer_,
            address[] memory assetsToReceive_
        )
    {
        if (
            _actionId ==
            uint256(IGmxLeveragePosition.GmxLeveragePositionActions.CreateIncreasePosition)
        ) {
            (
                address[] memory _path,
                address _indexToken,
                uint256 amount,
                ,
                ,
                ,
                ,
                uint256 executionFee,
                ,

            ) = __decodeCreateIncreasePositionActionArgs(_encodedActionArgs);

            require(
                __tokenIsSupportable(_path[0], _indexToken),
                "parseAssetsForAction: Unsupported pair"
            );
            // We do not validate whether an external position for the fund already exists,
            // but callers should be aware that one instance can be used for multiple nft positions

            assetsToTransfer_ = new address[](2);
            assetsToTransfer_[0] = _path[0];
            assetsToTransfer_[1] = getWethToken();

            amountsToTransfer_ = new uint256[](2);
            amountsToTransfer_[0] = amount;
            amountsToTransfer_[1] = executionFee;
        } else if (
            _actionId ==
            uint256(IGmxLeveragePosition.GmxLeveragePositionActions.CreateDecreasePosition)
        ) {
            (, , , , , , , uint256 executionFee, ) = __decodeCreateDecreaseActionArgs(
                _encodedActionArgs
            );

            //ToDO: validation

            assetsToTransfer_ = new address[](1);
            amountsToTransfer_ = new uint256[](1);
            assetsToReceive_ = new address[](1);

            assetsToTransfer_[0] = getWethToken();
            amountsToTransfer_[0] = executionFee;
            //Todo:
            // assetsToReceive_[0] = ;
        } else if (
            _actionId == uint256(IGmxLeveragePosition.GmxLeveragePositionActions.RemoveCollateral)
        ) {
            //ToDO: Fix this

            assetsToTransfer_ = new address[](0);
            amountsToTransfer_ = new uint256[](0);
            assetsToReceive_ = new address[](0);
            //Todo:
            // assetsToReceive_[0] = ;
        }

        return (assetsToTransfer_, amountsToTransfer_, assetsToReceive_);
    }

    /// @notice Parse and validate input arguments to be used when initializing a newly-deployed ExternalPositionProxy
    /// @dev Empty for this external position type
    function parseInitArgs(address, bytes memory) external override returns (bytes memory) {}

    // PRIVATE FUNCTIONS

    /// @dev Helper to determine if a pool is supportable, based on whether a trusted rate
    /// is available for its underlying token pair. Both of the underlying tokens must be supported,
    /// and at least one must be a supported primitive asset.
    function __tokenIsSupportable(
        address _tokenA,
        address _tokenB
    ) private view returns (bool isSupportable_) {
        IValueInterpreterGmxLeveragePosition valueInterpreterContract = IValueInterpreterGmxLeveragePosition(
                getValueInterpreter()
            );

        if (valueInterpreterContract.isSupportedPrimitiveAsset(_tokenA)) {
            if (valueInterpreterContract.isSupportedAsset(_tokenB)) {
                return true;
            }
        } else if (
            valueInterpreterContract.isSupportedDerivativeAsset(_tokenA) &&
            valueInterpreterContract.isSupportedPrimitiveAsset(_tokenB)
        ) {
            return true;
        }

        return false;
    }

    ///////////////////
    // STATE GETTERS //
    ///////////////////

    /// @notice Gets the `WETH_TOKEN` variable value
    /// @return _weth The `WETH_TOKEN` variable value
    function getWethToken() public view returns (address _weth) {
        return WETH_TOKEN;
    }

    /// @notice Gets the `VALUE_INTERPRETER` variable value
    /// @return valueInterpreter_ The `VALUE_INTERPRETER` variable value
    function getValueInterpreter() public view returns (address valueInterpreter_) {
        return VALUE_INTERPRETER;
    }
}

