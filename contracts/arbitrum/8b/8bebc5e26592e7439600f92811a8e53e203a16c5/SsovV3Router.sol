//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Libraries
import {SafeERC20} from "./SafeERC20.sol";

// Contracts
import {IERC721Receiver} from "./IERC721Receiver.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {Ownable} from "./Ownable.sol";
import {ContractWhitelist} from "./ContractWhitelist.sol";

// Interfaces
import {IERC20} from "./IERC20.sol";
import {ISsovV3} from "./ISsovV3.sol";
import {ISwap} from "./ISwap.sol";

/// @title SSOV V3 Router contract. Swaps are powered by 1inch.
contract SsovV3Router is
    ContractWhitelist,
    ReentrancyGuard,
    Ownable,
    IERC721Receiver
{
    using SafeERC20 for IERC20;

    uint256 public constant PERCENTAGE_PRECISION = 1e5;

    mapping(address => ISwap) public ssovToSwapContract;

    address public constant AGGREGATION_ROUTER_V5 =
        0x1111111254EEB25477B68fb85Ed929f73A960582;

    event SetSwapContract(address ssov, address swapContract);
    event ContractsSet(address _aggregator, address _ssovViewer);
    event EmergencyWithdraw(address sender);

    error OneInchSwapFailed();
    error SlippageExceeded();

    /*==== OWNER METHODS ====*/

    /// @notice Add a contract to the whitelist
    /// @dev Can only be called by the owner
    /// @param _contract Address of the contract that needs to be added to the whitelist
    function addToContractWhitelist(address _contract) external onlyOwner {
        _addToContractWhitelist(_contract);
    }

    /// @notice Remove a contract to the whitelist
    /// @dev Can only be called by the owner
    /// @param _contract Address of the contract that needs to be removed from the whitelist
    function removeFromContractWhitelist(address _contract) external onlyOwner {
        _removeFromContractWhitelist(_contract);
    }

    /// @notice Set a swap contract for a ssov
    /// @param _ssov the address of the ssov
    /// @param _swapContract the address of the swap contract
    function setSwapContract(
        address _ssov,
        address _swapContract
    ) external onlyOwner {
        ssovToSwapContract[_ssov] = ISwap(_swapContract);
        emit SetSwapContract(_ssov, _swapContract);
    }

    /// @notice Transfers all funds to msg.sender
    /// @dev Can only be called by the owner
    /// @param tokens The list of erc20 tokens to withdraw
    /// @param transferNative Whether should transfer the native currency
    function emergencyWithdraw(
        address[] calldata tokens,
        bool transferNative
    ) external onlyOwner {
        if (transferNative) payable(msg.sender).transfer(address(this).balance);

        IERC20 token;

        for (uint256 i; i < tokens.length; ) {
            token = IERC20(tokens[i]);
            token.safeTransfer(msg.sender, token.balanceOf(address(this)));

            unchecked {
                ++i;
            }
        }

        emit EmergencyWithdraw(msg.sender);
    }

    /*==== SWAP METHODS ====*/

    /// @notice Swap any token to the collateral token & purchase options
    /// @param _ssov The ssov to purchase from
    /// @param _srcToken The source token to swap from
    /// @param _dstToken The destination token to swap to
    /// @param _to The user to buy options for
    /// @param _strikeIndex The strike index of the options to buy
    /// @param _amount The amount of source token to swap to buy options
    /// @param _minReturnAmount The min amount of destination token to receive after the swap
    /// @param _swapData The swap data to execute on the 1inch aggregator
    function swapAndPurchase(
        ISsovV3 _ssov,
        address _srcToken,
        address _dstToken,
        address _to,
        uint256 _strikeIndex,
        uint256 _amount,
        uint256 _minReturnAmount,
        bytes calldata _swapData
    ) external payable nonReentrant {
        _isEligibleSender();

        IERC20 toToken = _ssov.collateralToken();
        IERC20 fromToken;
        bool nativeSrc = _srcToken ==
            0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

        if (!nativeSrc) {
            fromToken = IERC20(_srcToken);
            fromToken.safeTransferFrom(msg.sender, address(this), _amount);
        }

        if (_srcToken != _dstToken) {
            if (!nativeSrc) {
                fromToken.safeIncreaseAllowance(
                    address(AGGREGATION_ROUTER_V5),
                    _amount
                );
            }
            // solhint-disable-next-line avoid-low-level-calls
            (bool success, ) = address(AGGREGATION_ROUTER_V5).call{
                value: msg.value
            }(_swapData);

            if (!success) revert OneInchSwapFailed();
        }
        uint256 returnAmount = IERC20(_dstToken).balanceOf(address(this));

        if (returnAmount < _minReturnAmount) revert SlippageExceeded();

        if (address(toToken) != _dstToken) {
            IERC20(_dstToken).safeIncreaseAllowance(
                address(ssovToSwapContract[address(_ssov)]),
                returnAmount
            );
            returnAmount = ssovToSwapContract[address(_ssov)].swap(
                IERC20(_dstToken),
                returnAmount
            );
        }

        toToken.safeIncreaseAllowance(address(_ssov), returnAmount);

        uint256 amountOfOptions = computeAmountOfOptions(
            _ssov,
            _strikeIndex,
            returnAmount
        );

        _ssov.purchase(_strikeIndex, amountOfOptions, _to);

        _transferLeftoverBalances([_srcToken, _dstToken, address(toToken)]);
    }

    /// @notice Swap any token to the collateral token and deposit
    /// @param _ssov The ssov to purchase from
    /// @param _srcToken The source token to swap from
    /// @param _dstToken The destination token to swap to
    /// @param _to The user to deposit for
    /// @param _strikeIndex The strike index to deposit in
    /// @param _amount The amount of source token to swap to deposit
    /// @param _minReturnAmount The min amount of destination token to receive after the swap
    /// @param _swapData The swap data to execute on the 1inch aggregator
    function swapAndDeposit(
        ISsovV3 _ssov,
        address _srcToken,
        address _dstToken,
        address _to,
        uint256 _strikeIndex,
        uint256 _amount,
        uint256 _minReturnAmount,
        bytes calldata _swapData
    ) external payable nonReentrant {
        _isEligibleSender();

        IERC20 toToken = _ssov.collateralToken();
        IERC20 fromToken;
        bool nativeSrc = _srcToken ==
            0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

        if (!nativeSrc) {
            fromToken = IERC20(_srcToken);
            fromToken.safeTransferFrom(msg.sender, address(this), _amount);
        }

        if (_srcToken != _dstToken) {
            if (!nativeSrc) {
                fromToken.safeIncreaseAllowance(
                    address(AGGREGATION_ROUTER_V5),
                    _amount
                );
            }

            // solhint-disable-next-line avoid-low-level-calls
            (bool success, ) = address(AGGREGATION_ROUTER_V5).call{
                value: msg.value
            }(_swapData);

            if (!success) revert OneInchSwapFailed();
        }

        uint256 returnAmount = IERC20(_dstToken).balanceOf(address(this));

        if (returnAmount < _minReturnAmount) revert SlippageExceeded();

        if (address(toToken) != _dstToken) {
            IERC20(_dstToken).safeIncreaseAllowance(
                address(ssovToSwapContract[address(_ssov)]),
                _amount
            );
            returnAmount = ssovToSwapContract[address(_ssov)].swap(
                IERC20(_dstToken),
                returnAmount
            );
        }

        toToken.safeIncreaseAllowance(address(_ssov), returnAmount);
        _ssov.deposit(_strikeIndex, returnAmount, _to);

        _transferLeftoverBalances([_srcToken, _dstToken, address(toToken)]);
    }

    /// @notice Withdraw from multiple write position tokens
    /// @param _tokenIds the array of the token ids
    /// @param _ssov the address of the ssov
    function multiwithdraw(
        uint256[] calldata _tokenIds,
        ISsovV3 _ssov
    ) external nonReentrant {
        _isEligibleSender();

        for (uint256 i = 0; i < _tokenIds.length; i++) {
            _ssov.safeTransferFrom(msg.sender, address(this), _tokenIds[i]);
        }
        _ssov.setApprovalForAll(address(_ssov), true);
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            _ssov.withdraw(_tokenIds[i], msg.sender);
        }
    }

    /// @dev Computes the amount of options that can be purchased from some collateral amount
    /// @param _ssov The ssov
    /// @param _strikeIndex The strike index of options to be purchased
    /// @param _collateralAmount The collateral amount to be used to purchase options
    function computeAmountOfOptions(
        ISsovV3 _ssov,
        uint256 _strikeIndex,
        uint256 _collateralAmount
    ) public view returns (uint256 amountOfOptions) {
        uint256 epoch = _ssov.currentEpoch();
        uint256 strike = _ssov.getEpochData(epoch).strikes[_strikeIndex];
        (, uint256 expiry) = _ssov.getEpochTimes(epoch);
        uint256 costOfPurchasingOneOption = _ssov.calculatePremium(
            strike,
            100e18,
            expiry
        ) + _ssov.calculatePurchaseFees(strike, 100e18);

        amountOfOptions = ((_collateralAmount * 100e18) /
            costOfPurchasingOneOption);
    }

    /// @notice transfer leftover balances
    function _transferLeftoverBalances(address[3] memory _tokens) private {
        uint256 tokensLength = _tokens.length;

        for (uint256 i; i < tokensLength; ) {
            IERC20 token = IERC20(_tokens[i]);

            uint256 _bal = token.balanceOf(address(this));

            if (_bal > 0) {
                token.safeTransfer(msg.sender, _bal);
            }

            unchecked {
                ++i;
            }
        }

        // Transfer Native token back if any is remaining
        uint256 balance = address(this).balance;
        if (balance > 0) {
            payable(msg.sender).transfer(balance);
        }
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) public override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}

