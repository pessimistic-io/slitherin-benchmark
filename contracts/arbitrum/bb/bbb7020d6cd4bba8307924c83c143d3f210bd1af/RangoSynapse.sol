// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "./SynapseRouter.sol";
import "./RangoSynapseModels.sol";
import "./BaseContract.sol";
import "./IRangoSynapse.sol";
import "./IERC20.sol";

/// @title The root contract that handles Rango's interaction with Synapse bridge
/// @author Rango DeXter
/// @dev This is deployed as a separate contract from RangoV1
contract RangoSynapse is IRangoSynapse, BaseContract {

    /// @notice List of whitelisted Synapse routers in the current chain
    address public routerAddress;

    /// @notice The constructor of this contract that receives WETH address and initiates the settings
    /// @param _nativeWrappedAddress The address of WETH, WBNB, etc of the current network
    constructor(address _nativeWrappedAddress) {
        BaseContractStorage storage baseStorage = getBaseContractStorage();
        baseStorage.nativeWrappedAddress = _nativeWrappedAddress;
    }

    /// @notice Enables the contract to receive native ETH token from other contracts including WETH contract
    receive() external payable {}

    /// @notice update whitelisted Synapse router
    /// @param _address Synapse zap router
    function updateSynapseRouters(address _address) external onlyOwner {
        routerAddress = _address;
    }

    function uint2str(uint _i) internal pure returns (string memory _uintAsString) {
        if (_i == 0) {
            return "0";
        }
        uint j = _i;
        uint len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - _i / 10 * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }

    function toAsciiString(address x) internal pure returns (string memory) {
        bytes memory s = new bytes(40);
        for (uint i = 0; i < 20; i++) {
            bytes1 b = bytes1(uint8(uint(uint160(x)) / (2 ** (8 * (19 - i)))));
            bytes1 hi = bytes1(uint8(b) / 16);
            bytes1 lo = bytes1(uint8(b) - 16 * uint8(hi));
            s[2 * i] = char(hi);
            s[2 * i + 1] = char(lo);
        }
        return string(s);
    }

    function char(bytes1 b) internal pure returns (bytes1 c) {
        if (uint8(b) < 10) return bytes1(uint8(b) + 0x30);
        else return bytes1(uint8(b) + 0x57);
    }
    /// @inheritdoc IRangoSynapse
    function synapseBridge(
        address fromToken,
        uint inputAmount,
        RangoSynapseModels.SynapseBridgeRequest memory request
    ) external override payable whenNotPaused nonReentrant {
        require(routerAddress == request.router, 'Requested router address not whitelisted');
        require(request.to != NULL_ADDRESS, "Invalid recipient address");
        require(request.chainId != 0, "Invalid recipient chain");
        require(inputAmount > 0, "Invalid amount");
        //        if (fromToken == NULL_ADDRESS)
        //            require(msg.value > 0, "Invalid value"); // todo: check current value no msg.value

//        require(1 == 2, string.concat(
//                uint2str(inputAmount),
//                string(" "),
//                uint2str(IERC20(fromToken).balanceOf(address(this))),
//                string(" "),
//                uint2str(address(this).balance)
//            )
//        );

        if (fromToken != NULL_ADDRESS) {
            SafeERC20.safeTransferFrom(IERC20(fromToken), msg.sender, address(this), inputAmount);
            approve(fromToken, request.router, inputAmount);
        }

        SynapseRouter router = SynapseRouter(request.router);

        if (request.bridgeType == RangoSynapseModels.SynapseBridgeType.SWAP_AND_REDEEM)
            router.swapAndRedeem(
                request.to, request.chainId, IERC20(request.token), request.tokenIndexFrom,
                request.tokenIndexTo, inputAmount, request.minDy, request.deadline
            );
        else if (request.bridgeType == RangoSynapseModels.SynapseBridgeType.SWAP_AND_REDEEM_AND_SWAP)
            router.swapAndRedeemAndSwap(
                request.to, request.chainId, IERC20(request.token), request.tokenIndexFrom, request.tokenIndexTo,
                inputAmount, request.minDy, request.deadline, request.swapTokenIndexFrom, request.swapTokenIndexTo,
                request.swapMinDy, request.swapDeadline
            );
        else if (request.bridgeType == RangoSynapseModels.SynapseBridgeType.SWAP_AND_REDEEM_AND_REMOVE)
            router.swapAndRedeemAndRemove(
                request.to, request.chainId, IERC20(request.token), request.tokenIndexFrom, request.tokenIndexTo,
                inputAmount, request.minDy, request.deadline, request.swapTokenIndexFrom, request.minDy,
                request.swapDeadline
            );
        else if (request.bridgeType == RangoSynapseModels.SynapseBridgeType.REDEEM)
            router.redeem(request.to, request.chainId, IERC20(request.token), inputAmount);
        else if (request.bridgeType == RangoSynapseModels.SynapseBridgeType.REDEEM_AND_SWAP)
            router.redeemAndSwap(
                request.to, request.chainId, IERC20(request.token), inputAmount, request.tokenIndexFrom,
                request.tokenIndexTo, request.minDy, request.deadline
            );
        else if (request.bridgeType == RangoSynapseModels.SynapseBridgeType.REDEEM_AND_REMOVE)
            router.redeemAndRemove(
                request.to, request.chainId, IERC20(request.token), inputAmount, request.tokenIndexFrom,
                request.minDy, request.deadline
            );
        else if (request.bridgeType == RangoSynapseModels.SynapseBridgeType.DEPOSIT)
            router.deposit(request.to, request.chainId, IERC20(request.token), inputAmount);
        else if (request.bridgeType == RangoSynapseModels.SynapseBridgeType.DEPOSIT_ETH)
            router.depositETH{value : inputAmount}(request.to, request.chainId, inputAmount);
        else if (request.bridgeType == RangoSynapseModels.SynapseBridgeType.DEPOSIT_ETH_AND_SWAP)
            router.depositETHAndSwap{value : inputAmount}(
                request.to, request.chainId, inputAmount, request.tokenIndexFrom, request.tokenIndexTo, request.minDy,
                request.deadline
            );
        else if (request.bridgeType == RangoSynapseModels.SynapseBridgeType.DEPOSIT_AND_SWAP)
            router.depositAndSwap(
                request.to, request.chainId, IERC20(request.token), inputAmount, request.tokenIndexFrom,
                request.tokenIndexTo, request.minDy, request.deadline
            );
        else if (request.bridgeType == RangoSynapseModels.SynapseBridgeType.SWAP_ETH_AND_REDEEM)
            router.swapETHAndRedeem{value : inputAmount}(
                request.to, request.chainId, IERC20(request.token), request.tokenIndexFrom, request.tokenIndexTo,
                inputAmount, request.minDy, request.deadline
            );
        else if (request.bridgeType == RangoSynapseModels.SynapseBridgeType.ZAP_AND_DEPOSIT)
            router.zapAndDeposit(
                request.to, request.chainId, IERC20(request.token), request.liquidityAmounts, request.minDy,
                request.deadline
            );
        else if (request.bridgeType == RangoSynapseModels.SynapseBridgeType.ZAP_AND_DEPOSIT_AND_SWAP)
            router.zapAndDepositAndSwap(
                request.to, request.chainId, IERC20(request.token), request.liquidityAmounts, request.minDy,
                request.deadline, request.tokenIndexFrom, request.tokenIndexTo, request.swapMinDy, request.swapDeadline
            );
        else
            revert();


        //        emit RangoSynapseModels.SynapseBridgeEvent(
        //            request.bridgeType, inputToken, inputAmount, request.to, request.chainId, request.token,
        //            request.tokenIndexFrom, request.tokenIndexTo, request.minDy, request.deadline, request.swapTokenIndexFrom,
        //            request.swapTokenIndexTo, request.swapMinDy, request.swapDeadline);
    }
}
