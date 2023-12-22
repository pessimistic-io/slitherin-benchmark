// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.9;

import {     SwapOperation,     SwapProtocol,     InToken,     InInformation,     OutInformation,     InteractionOperation,     Operation,     InteractionOperation,     WrapperSelector,     WrapperSelectorAMM,     OneTokenSwapAMM } from "./structs.sol";
import {SwapHelper} from "./swapHelper.sol";
import {GenerateCallData} from "./generateCalldata.sol";
import {IERC20} from "./IERC20.sol";
import {IExecutor} from "./IExecutor.sol";
import {AccessControl} from "./AccessControl.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {Helpers} from "./helpers.sol";

/// @title  Router
/// @author Valha Team - octave@1608labs.xyz
/// @notice Router contract enabling to bundle Swap and DeFi interactions calls
contract Router is AccessControl, Helpers {
    uint24 private constant UNISWAP_V3_FEE = 3000;
    address constant nativeToken = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    uint256 constant MAX_FEE = 1e16; // 1e16
    uint256 constant FEE_UNITS = 1e18; // 1e18
    address payable referralSig;

    /// ============ Constructor ============

    // This need to be public so that it can be queried off_chain
    bytes32 public constant WHITELIST_ROLE = keccak256("WHITELIST_ROLE");

    // This stores the contract that will execute walls
    IExecutor executor;

    using SafeERC20 for IERC20;

    /// @notice Creates a new Router contract
    /// @param  _executor contract that will execute the sent calldata
    constructor(address _executor, address payable _referralSig) {
        referralSig = _referralSig;
        executor = IExecutor(_executor);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /// @notice modifier to let only whitelisted user to interact with the function
    modifier onlyWhitelist() {
        _checkRole(WHITELIST_ROLE);
        _;
    }

    /// ============ EVENTS ============

    event Referral(uint16 indexed referrer, uint80 fee);

    /// ============ Errors ============
    error InteractionError();
    error FeeToHigh();

    /// ============ Helpers ============
    function _transferTo(address token, uint256 amount, address to, uint80 fee, uint16 referral) internal {
        // 1.a
        if ((fee != 0) && referralSig != address(0)) {
            if (fee > MAX_FEE) revert FeeToHigh();
            uint256 feeAmount = (amount * fee) / FEE_UNITS;
            if (token != nativeToken) {
                _safeTransferFrom(token, msg.sender, referralSig, feeAmount);
            } else {
                referralSig.transfer(feeAmount);
            }
            emit Referral(referral, fee);
            amount -= feeAmount;
        }

        if (token != nativeToken) {
            _safeTransferFrom(token, msg.sender, to, amount);
        }
    }

    /// ============ Main Functions ============

    /// @notice Allows users to chain calls on-chain.
    /// @notice This function can chain swap and DeFi protocol interactions (deposit, redeem...)
    /// @dev    Requires user to approve contract.
    /// @dev    Dispatch the execution to the executor to avoid risk of hacks.
    /// @param  inInformation Information about the tokens used for initiating the call chain.
    ///         All the tokens in the object will be transferred to the contract if not native
    /// @param  routingCall contains all the swap and interaction information.
    ///         This object is at the center of the contract's logic
    /// @param  outInformation contains all the tokens that will be sent back to the msg.sender after all interactions.
    function multiRoute(
        InInformation memory inInformation, // Can't turn to calldata because of wrapper functions
        Operation[] memory routingCall, // Can't turn to calldata because of wrapper functions
        OutInformation memory outInformation // Can't turn to calldata because of wrapper functions
    ) public payable {
        // We transfer the tokens in the contract
        uint256 inTokenLength = inInformation.inTokens.length;
        for (uint256 i; i < inTokenLength; ++i) {
            _transferTo(
                inInformation.inTokens[i].tokenAddress,
                uint256(inInformation.inTokens[i].amount),
                address(executor),
                inInformation.fee,
                inInformation.referral
            );
        }

        if (outInformation.to == address(0)) {
            outInformation.to = msg.sender;
        }

        executor.execute(routingCall, outInformation);
    }

    /// ============ Helpers Functions ============

    /// @notice Get the balance of a specific user of a specified token
    /// @param  _token address of the token to check the balance of
    /// @param  _user address of the user to check the balance of
    /// @return balance of the _user for the specific _contract
    function _balanceOf(address _token, address _user) internal view returns (uint256 balance) {
        if (_token == nativeToken) {
            balance = _user.balance;
        } else {
            balance = IERC20(_token).balanceOf(_user);
        }
    }

    /// @notice Get the balance of this contract of a specified token
    /// @param  _token address of the token to check the balance of
    /// @return balance of the router for the specific _token
    function thisBalanceOf(address _token) internal view returns (uint256 balance) {
        return _balanceOf(_token, address(this));
    }

    /// @notice     Get the minimum of two provided uint256 values
    /// @param      a uint256 value
    /// @param      b uint256 value
    /// @return     The minimum value between a and b
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a <= b ? a : b;
    }

    /// @dev Callback for receiving Ether when the calldata is empty
    /// Because the owner can remove funds from the contract, we allow depositing funds here
    receive() external payable {}

    /// ================================================
    /// ================================================
    /// ================= L2 WRAPPERS ==================
    /// ================================================
    /// ================================================

    /// ============ l2Wrappers Functions ============

    /// @notice Allows a user to use multiRoute to deposit in a single token pool with fewer call
    /// arguments to reduce gas cost on l2
    /// @dev    Requires user to approve contract.
    /// @param  method_position_interaction Arguments for the selector, amount position
    ///         and interaction address in one bytes32
    ///    32 bits    8 bits        160 bits          56 bits
    /// | selector | position | interactionAddress | 0-padding |
    /// @param  amount_tokenOut Arguments for the amount and token_out in one bytes32
    ///      96 bits           160 bits
    /// |     amount      | tokenOutAddress |
    /// @param  referral_tokenIn Arguments for the referral_id, fee and token_in in one bytes32
    ///    16 bits             80 bits           160 bits
    /// | referral_id |    percentage_fee    | tokenInAddress |
    /// @param  callArgs contains the args in bytes32 necessary to execute the action on the underlying Protocol
    function deposit(
        bytes32 method_position_interaction,
        bytes32 amount_tokenOut,
        bytes32 referral_tokenIn,
        bytes32[] calldata callArgs
    ) external payable {
        InInformation memory inInfo;
        OutInformation memory outInfo;
        Operation[] memory args = new Operation[](1);
        address tokenIn;
        (tokenIn, inInfo, outInfo) = _decodeDepositParams(amount_tokenOut, referral_tokenIn);
        args[0] = _decodeInteractionOperation(method_position_interaction, tokenIn, callArgs);
        // call underlying multiRoute
        multiRoute(inInfo, args, outInfo);
    }

    /// @notice Allows a user to use multiRoute to swap and deposit in a single token pool with fewer call
    /// arguments to reduce gas cost on l2
    /// @dev    Requires user to approve contract.
    /// @param  method_position_interaction Arguments for the selector, amount position
    ///         and interaction address in one bytes32
    ///    32 bits    8 bits        160 bits          56 bits
    /// | selector | position | interactionAddress | 0-padding |
    /// @param  amount_tokenOut Arguments for the amount and token_out in one bytes32
    ///      96 bits           160 bits
    /// |     amount      | tokenOutAddress |
    /// @param  referral_tokenIn Arguments for the referral_id, fee and token_in in one bytes32
    ///    16 bits             80 bits           160 bits
    /// | referral_id |    percentage_fee    | tokenInAddress |
    /// @param  swapToken_min Arguments for the swap_token and amount minimum in one bytes32
    ///          96 bits               160 bits
    /// |     amountMinimum      |     swapToken     |
    /// @param  callArgs contains the args in bytes32 necessary to execute the action on the underlying Protocol
    function swapAndDeposit(
        bytes32 method_position_interaction,
        bytes32 amount_tokenOut,
        bytes32 referral_tokenIn,
        bytes32 swapToken_min,
        bytes32[] calldata callArgs
    ) external payable {
        address tokenIn;
        InInformation memory inInfo;
        Operation[] memory args = new Operation[](2);
        Operation memory argSwap;
        OutInformation memory outInfo;
        (tokenIn, inInfo, argSwap, outInfo) =
            _decodeSwapAndDepositParams(amount_tokenOut, referral_tokenIn, swapToken_min);
        args[0] = argSwap;
        args[1] = _decodeInteractionOperation(method_position_interaction, tokenIn, callArgs);
        // call underlying multiRoute
        multiRoute(inInfo, args, outInfo);
    }

    /// @notice Allows a user to use multiRoute to redeem and swap in a single token pool with fewer call
    /// arguments to reduce gas cost on l2
    /// @dev    Requires user to approve contract.
    /// @param  method_position_interaction Arguments for the selector, amount position
    ///         and interaction address in one bytes32
    ///    32 bits    8 bits        160 bits          56 bits
    /// | selector | position | interactionAddress | 0-padding |
    /// @param  amount_tokenOut Arguments for the amount and token_out in one bytes32
    ///      96 bits           160 bits
    /// |     amount      | tokenOutAddress |
    /// @param  referral_tokenIn Arguments for the referral_id, fee and token_in in one bytes32
    ///    16 bits             80 bits           160 bits
    /// | referral_id |    percentage_fee    | tokenInAddress |
    /// @param  swapToken_min Arguments for the swap_token and amount minimum in one bytes32
    ///          96 bits               160 bits
    /// |     amountMinimum      |     swapToken     |
    /// @param  callArgs contains the args in bytes32 necessary to execute the action on the underlying Protocol
    function redeemAndSwap(
        bytes32 method_position_interaction,
        bytes32 amount_tokenOut,
        bytes32 referral_tokenIn,
        bytes32 swapToken_min,
        bytes32[] calldata callArgs
    ) external payable {
        InInformation memory inInfo;
        Operation[] memory args = new Operation[](2);
        Operation memory argSwap;
        OutInformation memory outInfo;
        address tokenIn;
        (tokenIn, inInfo, argSwap, outInfo) =
            _decodeRedeemAndSwapParams(amount_tokenOut, referral_tokenIn, swapToken_min);
        args[0] = _decodeInteractionOperation(method_position_interaction, tokenIn, callArgs);
        args[1] = argSwap;
        multiRoute(inInfo, args, outInfo);
    }

    /// @notice Allows a user to use multiRoute to deposit in a two tokens pool with fewer call
    /// arguments to reduce gas cost on l2
    /// @dev    Requires user to approve contract.
    /// @param  method_interaction Arguments for the selector and interaction address in one bytes32
    ///    32 bits        160 bits          64 bits
    /// | selector |  interactionAddress | 0-padding |
    /// @param  referral_poolToken Arguments for the referral_id, fee and pool_token in one bytes32
    ///    16 bits             80 bits           160 bits
    /// | referral_id |    percentage_fee    | tokenInAddress |
    /// @param  tokensIn contains the tokens that the user needs to use to enter the pool
    /// @param  amountsIn contains the amounts that the user wants to use to enter the pool
    /// @param  callArgs contains the args in bytes32 necessary to execute the action on the underlying Protocol
    function depositAMM(
        bytes32 method_interaction,
        bytes32 referral_poolToken,
        uint8[4] calldata amountPositions,
        address[] calldata tokensIn,
        uint96[] calldata amountsIn,
        bytes32[] calldata callArgs
    ) external payable {
        InInformation memory inInfo;
        OutInformation memory outInfo;
        Operation[] memory args = new Operation[](1);
        (inInfo, outInfo) = _decodeDepositInOutParams(referral_poolToken, tokensIn, amountsIn);
        args[0] = _decodeDepositInteractionOperationAMM(method_interaction, amountPositions, tokensIn, callArgs);
        multiRoute(inInfo, args, outInfo);
    }

    /// @notice Allows a user to use multiRoute to deposit in a two tokens pool with only one token and fewer call
    /// arguments to reduce gas cost on l2
    /// @dev    Requires user to approve contract.
    /// @param  method_interaction Arguments for the selector and interaction address in one bytes32
    ///    32 bits        160 bits          64 bits
    /// | selector |  interactionAddress | 0-padding |
    /// @param  referral_poolToken Arguments for the referral_id, fee and pool_token in one bytes32
    ///    16 bits             80 bits           160 bits
    /// | referral_id |    percentage_fee    | tokenInAddress |
    /// @param  swap_in Arguments for the amount and swap_token_in in one bytes32
    ///      96 bits           160 bits
    /// |     amount      |   swapTokenIn |
    /// @param  swap_min Arguments for the minimum_amount and swap_token_out in one bytes32
    ///       96 bits               160 bits
    /// |  minimum_amount      | swapTokenOut |
    /// @param  amountPositions contains the positions of amounts value in _callArgs
    /// @param  tokensIn contains the tokens that the user needs to use to enter the pool
    /// @param  amountsIn contains the amounts that the user wants to use to enter the pool
    /// @param  callArgs contains the args in bytes32 necessary to execute the action on the underlying Protocol
    function swapAndDepositAMM(
        bytes32 method_interaction,
        bytes32 referral_poolToken,
        bytes32 swap_in,
        bytes32 swap_min,
        uint8[4] calldata amountPositions,
        address[] calldata tokensIn,
        uint96[] calldata amountsIn,
        bytes32[] calldata callArgs
    ) external payable {
        InInformation memory inInfo;
        Operation[] memory args = new Operation[](2);
        OutInformation memory outInfo;
        (inInfo, outInfo) = _decodeDepositInOutParams(referral_poolToken, tokensIn, amountsIn);
        args[0] = _decodeSwapOperationAMM(swap_in, swap_min);
        args[1] = _decodeDepositInteractionOperationAMM(method_interaction, amountPositions, tokensIn, callArgs);
        multiRoute(inInfo, args, outInfo);
    }

    /// @notice Allows a user to use multiRoute to redeem from a two tokens pool with only one token and fewer call
    /// arguments to reduce gas cost on l2
    /// @dev    Requires user to approve contract.
    /// @param  method_interaction Arguments for the selector and interaction address in one bytes32
    ///    32 bits        160 bits          64 bits
    /// | selector |  interactionAddress | 0-padding |
    /// @param  referral_poolToken Arguments for the referral_id, fee and pool_token in one bytes32
    ///    16 bits             80 bits           160 bits
    /// | referral_id |    percentage_fee    | tokenInAddress |
    /// @param  swap_in Arguments for the amount and swap_token_in in one bytes32
    ///      96 bits           160 bits
    /// |     amount      |   swapTokenIn |
    /// @param  swap_min Arguments for the minimum_amount and swap_token_out in one bytes32
    ///       96 bits               160 bits
    /// |  minimum_amount      | swapTokenOut |
    /// @param  amount is the amount the user wants to redeem from the pool
    /// @param  callArgs contains the args in bytes32 necessary to execute the action on the underlying Protocol
    function redeemAndSwapAMM(
        bytes32 method_interaction,
        bytes32 referral_poolToken,
        bytes32 swap_in,
        bytes32 swap_min,
        uint8[4] calldata amountPositions,
        uint96 amount,
        bytes32[] calldata callArgs
    ) external payable {
        InInformation memory inInfo;
        Operation[] memory args = new Operation[](2);
        OutInformation memory outInfo;

        (inInfo, outInfo) = _decodeRedeemInOutParams(referral_poolToken, swap_min, amount);
        args[0] =
            _decodeRedeemInteractionOperationAMM(method_interaction, referral_poolToken, amountPositions, callArgs);
        args[1] = _decodeSwapOperationAMM(swap_in, swap_min);
        multiRoute(inInfo, args, outInfo);
    }

    /// ============ Wrappers Internal Functions ============

    /// @notice Decodes compressed interaction params to standard Operation object
    /// @param  method_position_interaction Arguments for the selector, amount position
    ///         and interaction address in one bytes32
    /// @param  tokenIn token entering the router for this specified interaction
    /// @param  callArgs contains the args in bytes32 necessary to execute the action on the underlying Protocol
    /// @return the Operation object to send to multiRoute function
    function _decodeInteractionOperation(
        bytes32 method_position_interaction,
        address tokenIn,
        bytes32[] calldata callArgs
    ) internal pure returns (Operation memory) {
        bytes4 methodSelector = bytes4(method_position_interaction);
        uint8 amountPosition;
        address interactionAddress;
        assembly {
            interactionAddress := and(shr(56, method_position_interaction), 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
            amountPosition := and(shr(216, method_position_interaction), 0xFF)
        }
        Operation memory argDeposit;
        argDeposit.interaction = new InteractionOperation[](1);
        address[] memory addressesArray = new address[](1);
        addressesArray[0] = tokenIn;
        argDeposit.interaction[0] = InteractionOperation(
            callArgs, methodSelector, interactionAddress, [amountPosition, 0, 0, 0], addressesArray
        );
        return argDeposit;
    }

    /// @notice Decodes compressed deposit params to standard InInformation and OutInformation objects
    /// @param  amount_tokenOut Arguments for the amount and token_out in one bytes32
    /// @param  referral_tokenIn Arguments for the referral_id, fee and token_in in one bytes32
    /// @return the tokenIn, the InInformation object, the OutInformation object
    function _decodeDepositParams(bytes32 amount_tokenOut, bytes32 referral_tokenIn)
        internal
        pure
        returns (address, InInformation memory, OutInformation memory)
    {
        address tokenOut;
        uint96 amount;
        assembly {
            tokenOut := and(amount_tokenOut, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
            amount := and(shr(160, amount_tokenOut), 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
        }
        address tokenIn;
        uint80 fee;
        uint16 referral;
        assembly {
            tokenIn := and(referral_tokenIn, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
            fee := and(shr(160, referral_tokenIn), 0xFFFFFFFFFFFFFFFFFF)
            referral := and(shr(240, referral_tokenIn), 0xFFFF)
        }
        InInformation memory inInfo;
        inInfo.inTokens = new InToken[](1);
        inInfo.referral = referral;
        inInfo.fee = fee;
        inInfo.inTokens[0] = InToken(tokenIn, uint96(amount));

        OutInformation memory outInfo;
        outInfo.tokens = new address[](1);
        outInfo.tokens[0] = tokenOut;

        return (tokenIn, inInfo, outInfo);
    }

    /// @notice Decodes compressed SwapAndDeposit params to standard InInformation and OutInformation
    ///         objects and Operation object for the initial swap
    /// @param  amount_tokenOut Arguments for the amount and token_out in one bytes32
    /// @param  referral_tokenIn Arguments for the referral_id, fee and token_in in one bytes32
    /// @param  swapToken_min Arguments for the swap_token and amount minimum in one bytes32
    /// @return the tokenIn, the InInformation object, the Interaction object for swap, the OutInformation object
    function _decodeSwapAndDepositParams(bytes32 amount_tokenOut, bytes32 referral_tokenIn, bytes32 swapToken_min)
        internal
        pure
        returns (address, InInformation memory, Operation memory, OutInformation memory)
    {
        address tokenOut;
        uint96 amount;
        assembly {
            tokenOut := and(amount_tokenOut, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
            amount := and(shr(160, amount_tokenOut), 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
        }
        address tokenIn;
        uint80 fee;
        uint16 referral;
        assembly {
            tokenIn := and(referral_tokenIn, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
            fee := and(shr(160, referral_tokenIn), 0xFFFFFFFFFFFFFFFFFF)
            referral := and(shr(240, referral_tokenIn), 0xFFFF)
        }
        address swapToken;
        uint96 amountMin;
        assembly {
            swapToken := and(swapToken_min, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
            amountMin := and(shr(160, swapToken_min), 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
        }

        InInformation memory inInfo;
        inInfo.inTokens = new InToken[](1);
        inInfo.referral = referral;
        inInfo.fee = fee;
        inInfo.inTokens[0] = InToken(swapToken, uint96(amount));

        Operation memory argSwap;
        argSwap.swap = new SwapOperation[](1);
        argSwap.swap[0] = (
            SwapOperation(
                swapToken, //address inToken;
                amount, //uint256 maxInAmount;
                tokenIn, //address outToken;
                amountMin, //uint256 minOutAmount;
                SwapProtocol.UniswapV3, //SwapProtocol protocol;
                abi.encode(uint24(3000)) //bytes args;
            )
        );

        OutInformation memory outInfo;
        outInfo.tokens = new address[](1);
        outInfo.tokens[0] = tokenOut;

        return (tokenIn, inInfo, argSwap, outInfo);
    }

    /// @notice Decodes compressed RedeemAndSwap params to standard InInformation and OutInformation
    ///         objects and Operation object for the final swap
    /// @param  amount_tokenOut Arguments for the amount and token_out in one bytes32
    /// @param  referral_tokenIn Arguments for the referral_id, fee and token_in in one bytes32
    /// @param  swapToken_min Arguments for the swap_token and amount minimum in one bytes32
    /// @return the tokenIn, the InInformation object, the Interaction object for swap, the OutInformation object
    function _decodeRedeemAndSwapParams(bytes32 amount_tokenOut, bytes32 referral_tokenIn, bytes32 swapToken_min)
        internal
        pure
        returns (address, InInformation memory, Operation memory, OutInformation memory)
    {
        address tokenOut;
        uint96 amount;
        assembly {
            tokenOut := and(amount_tokenOut, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
            amount := and(shr(160, amount_tokenOut), 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
        }
        address tokenIn;
        uint80 fee;
        uint16 referral;
        assembly {
            tokenIn := and(referral_tokenIn, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
            fee := and(shr(160, referral_tokenIn), 0xFFFFFFFFFFFFFFFFFF)
            referral := and(shr(240, referral_tokenIn), 0xFFFF)
        }
        address swapToken;
        uint96 amountMin;
        assembly {
            swapToken := and(swapToken_min, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
            amountMin := and(shr(160, swapToken_min), 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
        }

        InInformation memory inInfo;
        inInfo.inTokens = new InToken[](1);
        inInfo.referral = referral;
        inInfo.fee = fee;
        inInfo.inTokens[0] = InToken(tokenIn, uint96(amount));

        Operation memory argSwap;
        argSwap.swap = new SwapOperation[](1);
        argSwap.swap[0] = (
            SwapOperation(
                tokenOut, type(uint256).max, swapToken, amountMin, SwapProtocol.UniswapV3, abi.encode(uint24(3000))
            )
        );

        OutInformation memory outInfo;
        outInfo.tokens = new address[](1);
        outInfo.tokens[0] = swapToken;

        return (tokenIn, inInfo, argSwap, outInfo);
    }

    /// @notice Decodes compressed Swap Operation params to standard Operation object for AMM
    /// @param  swap_in Arguments for the amount and swap_token_in in one bytes32
    /// @param  swap_min Arguments for the minimum_amount and swap_token_out in one bytes32
    /// @return the Operation object for the swap
    function _decodeSwapOperationAMM(bytes32 swap_in, bytes32 swap_min) internal pure returns (Operation memory) {
        address swapTokenIn;
        uint96 swapAmount;
        assembly {
            swapTokenIn := and(swap_in, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
            swapAmount := and(shr(160, swap_in), 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
        }
        address swapTokenOut;
        uint96 amountMin;
        assembly {
            swapTokenOut := and(swap_min, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
            amountMin := and(shr(160, swap_min), 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
        }
        Operation memory argSwap;
        argSwap.swap = new SwapOperation[](1);
        argSwap.swap[0] = (
            SwapOperation(
                swapTokenIn, swapAmount, swapTokenOut, amountMin, SwapProtocol.UniswapV3, abi.encode(uint24(3000))
            )
        );

        return argSwap;
    }

    /// @notice Decodes compressed Deposit params to standard InInformation and OutInformation for AMM
    ///         objects and Operation object for the final swap
    /// @param  referral_poolToken Arguments for the referral_id, fee and pool_token in one bytes32
    /// @param  tokensIn contains the tokens that the user needs to use to enter the pool
    /// @param  amountsIn contains the amounts that the user wants to use to enter the pool
    /// @return the InInformation object and the OutInformation object
    function _decodeDepositInOutParams(
        bytes32 referral_poolToken,
        address[] calldata tokensIn,
        uint96[] calldata amountsIn
    ) internal pure returns (InInformation memory, OutInformation memory) {
        address poolToken;
        uint80 fee;
        uint16 referral;
        assembly {
            poolToken := and(referral_poolToken, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
            fee := and(shr(160, referral_poolToken), 0xFFFFFFFFFFFFFFFFFF)
            referral := and(shr(240, referral_poolToken), 0xFFFF)
        }
        InInformation memory inInfo;
        inInfo.inTokens = new InToken[](tokensIn.length);
        for (uint256 i = 0; i < tokensIn.length; i++) {
            inInfo.inTokens[i] = InToken(tokensIn[i], amountsIn[i]);
        }
        inInfo.referral = referral;
        inInfo.fee = fee;

        OutInformation memory outInfo;
        outInfo.tokens = new address[](1);
        outInfo.tokens[0] = poolToken;

        return (inInfo, outInfo);
    }

    /// @notice Decodes compressed Deposit Operation params to standard Operation object for AMM
    /// @param  method_interaction Arguments for the selector and interaction address in one bytes32
    /// @param  amountPositions contains the positions of amounts value in _callArgs
    /// @param  tokensIn contains the tokens that the user needs to use to enter the pool
    /// @param  callArgs contains the args in bytes32 necessary to execute the action on the underlying Protocol
    /// @return the Operation object for the deposit
    function _decodeDepositInteractionOperationAMM(
        bytes32 method_interaction,
        uint8[4] calldata amountPositions,
        address[] calldata tokensIn,
        bytes32[] calldata callArgs
    ) internal pure returns (Operation memory) {
        bytes4 methodSelector = bytes4(method_interaction);
        address interactionAddress;
        assembly {
            interactionAddress := and(shr(64, method_interaction), 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
        }
        Operation memory arg;
        arg.interaction = new InteractionOperation[](1);
        arg.interaction[0] =
            (InteractionOperation(callArgs, methodSelector, interactionAddress, amountPositions, tokensIn));

        return arg;
    }

    /// @notice Decodes compressed Redeem params to standard InInformation and OutInformation for AMM
    ///         objects and Operation object for the final swap
    /// @param  referral_poolToken Arguments for the referral_id, fee and pool_token in one bytes32
    /// @param  swap_min Arguments for the minimum_amount and swap_token_out in one bytes32
    /// @param  amount contains the amount that the user wants to redeem from the pool
    /// @return the InInformation object and the OutInformation object
    function _decodeRedeemInOutParams(bytes32 referral_poolToken, bytes32 swap_min, uint96 amount)
        internal
        pure
        returns (InInformation memory, OutInformation memory)
    {
        address poolToken;
        uint80 fee;
        uint16 referral;
        assembly {
            poolToken := and(referral_poolToken, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
            fee := and(shr(160, referral_poolToken), 0xFFFFFFFFFFFFFFFFFF)
            referral := and(shr(240, referral_poolToken), 0xFFFF)
        }
        address swapTokenOut;
        assembly {
            swapTokenOut := and(swap_min, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
        }
        InInformation memory inInfo;
        inInfo.inTokens = new InToken[](1);
        inInfo.inTokens[0] = InToken(poolToken, amount);
        inInfo.referral = referral;
        inInfo.fee = fee;

        OutInformation memory outInfo;
        outInfo.tokens = new address[](1);
        outInfo.tokens[0] = swapTokenOut;

        return (inInfo, outInfo);
    }

    /// @notice Decodes compressed Redeem Operation params to standard Operation object for AMM
    /// @param  method_interaction Arguments for the selector and interaction address in one bytes32
    /// @param  referral_poolToken Arguments for the referral_id, fee and pool_token in one bytes32
    /// @param  amountPositions contains the positions of amounts value in _callArgs
    /// @param  callArgs contains the args in bytes32 necessary to execute the action on the underlying Protocol
    /// @return the Operation object for the redeem
    function _decodeRedeemInteractionOperationAMM(
        bytes32 method_interaction,
        bytes32 referral_poolToken,
        uint8[4] calldata amountPositions,
        bytes32[] calldata callArgs
    ) internal pure returns (Operation memory) {
        bytes4 methodSelector = bytes4(method_interaction);
        address interactionAddress;
        assembly {
            interactionAddress := and(shr(64, method_interaction), 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
        }
        address poolToken;
        assembly {
            poolToken := and(referral_poolToken, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
        }

        address[] memory addressesArray = new address[](1);
        addressesArray[0] = poolToken;
        Operation memory arg;
        arg.interaction = new InteractionOperation[](1);
        arg.interaction[0] =
            (InteractionOperation(callArgs, methodSelector, interactionAddress, amountPositions, addressesArray));

        return arg;
    }
}

