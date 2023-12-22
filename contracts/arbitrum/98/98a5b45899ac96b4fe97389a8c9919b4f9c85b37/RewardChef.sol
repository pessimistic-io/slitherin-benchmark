// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./SafeERC20Upgradeable.sol";
import "./PausableUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./SafeMathUpgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";

import "./IRewardChef.sol";

interface IUniswapV2Router02 {
    function getAmountsOut(
        uint amountIn,
        address[] memory path
    ) external view returns (uint[] memory amounts);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        address referrer,
        uint deadline
    ) external;
}

contract RewardChef is
    IRewardChef,
    Initializable,
    PausableUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMathUpgradeable for uint256;

    IERC20Upgradeable public UWU;
    address public dynamicRewardWallet;
    IUniswapV2Router02 public uniswapRouter;
    mapping(address => bool) public whitelistedTokens;

    uint256 public maxSlippagePercent;
    uint256 public constant SLIPPAGE_DENOMINATOR = 100;

    event TokenCooked(
        address indexed tokenIn,
        uint256 amountIn
    );

    function initialize(
        IERC20Upgradeable _UWU,
        address _dynamicRewardWallet,
        IUniswapV2Router02 _uniswapRouter,
        uint256 _maxSlippagePercent
    ) external initializer {
        __UUPSUpgradeable_init();
        __Ownable_init();
        __Pausable_init();

        UWU = _UWU;
        dynamicRewardWallet = _dynamicRewardWallet;
        uniswapRouter = _uniswapRouter;
        maxSlippagePercent = _maxSlippagePercent;
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    /**
     * @dev Pauses the contract, preventing certain actions from being performed.
     */
    function pause() public onlyOwner {
        _pause();
    }

    /**
     * @dev Unpauses the contract, allowing certain actions to be performed again.
     */
    function unpause() public onlyOwner {
        _unpause();
    }

    /**
     * @dev Sets a new address for the dynamic reward wallet.
     * @param _dynamicRewardWallet The new address for the dynamic reward wallet.
     */
    function setDynamicRewardWallet(
        address _dynamicRewardWallet
    ) external onlyOwner {
        dynamicRewardWallet = _dynamicRewardWallet;
    }

    /**
     * @dev Sets the maximum slippage percentage for token swaps.
     * @param _maxSlippagePercent The new maximum slippage percentage.
     */
    function setMaxSlippagePercent(
        uint256 _maxSlippagePercent
    ) external onlyOwner {
        maxSlippagePercent = _maxSlippagePercent;
    }

    /**
     * @dev Adds a token to the whitelist.
     * @param _token The address of the token to add to the whitelist.
     */
    function addWhitelistedToken(address _token) external onlyOwner {
        whitelistedTokens[_token] = true;
    }

    /**
     * @dev Removes a token from the whitelist.
     * @param _token The address of the token to remove from the whitelist.
     */
    function removeWhitelistedToken(address _token) external onlyOwner {
        delete whitelistedTokens[_token];
    }

    /**
     * @dev Returns true if the given token is whitelisted, otherwise returns false.
     * @param _token The address of the token to check.
     * @return A boolean value indicating whether the token is whitelisted or not.
     */
    function isWhitelisted(address _token) public view returns (bool) {
        return whitelistedTokens[_token];
    }

    /**
     * @dev Swaps the given input token for UWU tokens and sends the output to the dynamic reward wallet.
     * @param _tokenIn The address of the input token.
     * @param _amountIn The amount of input tokens to swap.
     */
    function cookTokens(
        address _tokenIn,
        uint256 _amountIn
    ) external override whenNotPaused {
        require(whitelistedTokens[_tokenIn], "Token not whitelisted");
        require(
            dynamicRewardWallet != address(0),
            "Dynamic reward wallet not found"
        );
        IERC20Upgradeable tokenIn = IERC20Upgradeable(_tokenIn);

        tokenIn.safeIncreaseAllowance(address(uniswapRouter), _amountIn);

        address[] memory path = new address[](2);
        path[0] = _tokenIn;
        path[1] = address(UWU);

        uint256[] memory amountsOut = uniswapRouter.getAmountsOut(
            _amountIn,
            path
        );
        uint256 amountOutMin = amountsOut[1]
            .mul(SLIPPAGE_DENOMINATOR.sub(maxSlippagePercent))
            .div(SLIPPAGE_DENOMINATOR);

        uniswapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            _amountIn,
            amountOutMin,
            path,
            dynamicRewardWallet,
            address(this),
            block.timestamp
        );

        emit TokenCooked(_tokenIn, _amountIn);
    }

    /**
     * @dev Withdraws the specified amount of UWU tokens to the owner.
     * @param _amount The amount of UWU tokens to withdraw.
     */
    function withdrawUWU(uint256 _amount) external override onlyOwner {
        UWU.safeTransfer(msg.sender, _amount);
    }

    /**
     * @dev Withdraws the specified amount of a whitelisted token to the owner.
     * @param _token The address of the token to withdraw.
     * @param _amount The amount of tokens to withdraw.
     */
    function withdrawToken(
        address _token,
        uint256 _amount
    ) external override onlyOwner {
        require(isWhitelisted(_token), "Token not whitelisted");

        IERC20Upgradeable token = IERC20Upgradeable(_token);
        token.safeTransfer(msg.sender, _amount);
    }
}

