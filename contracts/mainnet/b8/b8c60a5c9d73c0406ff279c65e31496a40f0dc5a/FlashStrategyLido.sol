// SPDX-License-Identifier: BUSL-1.1
// Licensor: Flashstake DAO
// Licensed Works: (this contract, source below)
// Change Date: The earlier of 2026-12-01 or a date specified by Flashstake DAO publicly
// Change License: GNU General Public License v2.0 or later
pragma solidity ^0.8.4;

import "./Ownable.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./IFlashFToken.sol";
import "./IUserIncentive.sol";
import "./IFlashStrategy.sol";

contract FlashStrategyLido is IFlashStrategy, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address immutable flashProtocolAddress;
    address immutable principalTokenAddress;
    address fTokenAddress;
    uint256 principalBalance;

    uint256 maxStakeDuration = 7776000; // Maximum stake duration for this strategy
    bool public maxStakeDurationLocked = false; // Determines if the above variable is locked (stop future updates)

    address public userIncentiveAddress; // User Incentive contract address
    bool public userIncentiveAddressLocked; // Determines if the above variable is locked (stop future updates)

    constructor(address _flashProtocolAddress, address _principalTokenAddress) public {
        flashProtocolAddress = _flashProtocolAddress;
        principalTokenAddress = _principalTokenAddress;
    }

    function depositPrincipal(uint256 _tokenAmount) external override onlyAuthorised returns (uint256) {
        // Lido: 1 wei corner case
        // stETH balance calculation includes integer division, and there is a common case
        // when the whole stETH balance can't be transferred from the account, while leaving
        // the last 1 wei on the sender's account. Same thing can actually happen at any
        // transfer or deposit transaction.
        // ref: https://docs.lido.fi/guides/steth-integration-guide/

        // Register how much we are depositing
        principalBalance = principalBalance + _tokenAmount - 1;

        return _tokenAmount - 1;
    }

    function withdrawYield(uint256 _tokenAmount) private {
        // No actual "withdrawal" needed since yield is calculated as the difference between
        // deposited stETH and current balance (post rebase)
        // No interaction with Lido needed since stETH rebases

        // Ensure the stETH balance after deducting _tokenAmount is greater than tracked principalBalance
        require(IERC20(principalTokenAddress).balanceOf(address(this)) - _tokenAmount >= principalBalance);
    }

    function withdrawPrincipal(uint256 _tokenAmount) external override onlyAuthorised {
        require(_tokenAmount <= principalBalance, "WITHDRAW TOO HIGH");

        // No actual "withdrawal" needed since yield is calculated as the difference between
        // deposited stETH and current balance (post rebase)
        // No interaction with Lido needed since stETH rebases

        IERC20(principalTokenAddress).safeTransfer(msg.sender, _tokenAmount);

        principalBalance = principalBalance - _tokenAmount;
    }

    function withdrawERC20(address[] calldata _tokenAddresses, uint256[] calldata _tokenAmounts) external onlyOwner {
        require(_tokenAddresses.length == _tokenAmounts.length, "ARRAY SIZE MISMATCH");

        for (uint256 i = 0; i < _tokenAddresses.length; i++) {
            // Ensure the token being withdrawn is not the principal token
            require(_tokenAddresses[i] != principalTokenAddress, "TOKEN ADDRESS PROHIBITED");

            // Transfer the token to the caller
            IERC20(_tokenAddresses[i]).safeTransfer(msg.sender, _tokenAmounts[i]);
        }
    }

    function getPrincipalBalance() public view override returns (uint256) {
        return principalBalance;
    }

    function getYieldBalance() public view override returns (uint256) {
        return IERC20(principalTokenAddress).balanceOf(address(this)) - principalBalance;
    }

    function getPrincipalAddress() external view override returns (address) {
        return principalTokenAddress;
    }

    function getFTokenAddress() external view returns (address) {
        return fTokenAddress;
    }

    function setFTokenAddress(address _fTokenAddress) external override onlyAuthorised {
        require(fTokenAddress == address(0), "FTOKEN ADDRESS ALREADY SET");
        fTokenAddress = _fTokenAddress;
    }

    function quoteMintFToken(uint256 _tokenAmount, uint256 _duration) external pure override returns (uint256) {
        // Enforce minimum _duration
        require(_duration >= 60, "DURATION TOO LOW");

        // 1 ERC20 for 365 DAYS = 1 fERC20
        // 1 second = 0.000000031709792000
        // eg (100000000000000000 * (1 second * 31709792000)) / (10**principalDecimals)
        return (_tokenAmount * (_duration * 31709792000)) / (10**18);
    }

    function quoteBurnFToken(uint256 _tokenAmount) public view override returns (uint256) {
        uint256 totalSupply = IERC20(fTokenAddress).totalSupply();
        require(totalSupply > 0, "INSUFFICIENT fERC20 TOKEN SUPPLY");

        if (_tokenAmount > totalSupply) {
            _tokenAmount = totalSupply;
        }

        // Calculate the percentage of _tokenAmount vs totalSupply provided
        // and multiply by total yield
        return (getYieldBalance() * _tokenAmount) / totalSupply;
    }

    function burnFToken(
        uint256 _tokenAmount,
        uint256 _minimumReturned,
        address _yieldTo
    ) external override nonReentrant returns (uint256) {
        // Calculate how much yield to give back
        uint256 tokensOwed = quoteBurnFToken(_tokenAmount);
        require(tokensOwed >= _minimumReturned, "INSUFFICIENT OUTPUT");

        // Transfer fERC20 (from caller) tokens to contract so we can burn them
        IFlashFToken(fTokenAddress).burnFrom(msg.sender, _tokenAmount);

        withdrawYield(tokensOwed);
        IERC20(principalTokenAddress).safeTransfer(_yieldTo, tokensOwed);

        // Distribute rewards if there is a reward balance within contract
        if (userIncentiveAddress != address(0)) {
            IUserIncentive(userIncentiveAddress).claimReward(_tokenAmount, _yieldTo);
        }

        emit BurnedFToken(msg.sender, _tokenAmount, tokensOwed);

        return tokensOwed;
    }

    modifier onlyAuthorised() {
        require(msg.sender == flashProtocolAddress || msg.sender == address(this), "NOT FLASH PROTOCOL");
        _;
    }

    function getMaxStakeDuration() public view override returns (uint256) {
        return maxStakeDuration;
    }

    function setMaxStakeDuration(uint256 _newMaxStakeDuration) external onlyOwner {
        require(maxStakeDurationLocked == false);
        maxStakeDuration = _newMaxStakeDuration;
    }

    function lockMaxStakeDuration() external onlyOwner {
        maxStakeDurationLocked = true;
    }

    function setUserIncentiveAddress(address _userIncentiveAddress) external onlyOwner {
        require(userIncentiveAddressLocked == false);
        userIncentiveAddress = _userIncentiveAddress;
    }

    function lockSetUserIncentiveAddress() external onlyOwner {
        require(userIncentiveAddressLocked == false);
        userIncentiveAddressLocked = true;
    }
}

