// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "./IERC20Metadata.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./IFlashStrategy.sol";
import "./IFlashFToken.sol";
import "./FlashStrategyAdmin.sol";
import "./IRewardRouter.sol";
import "./IRewardRouterV2.sol";

contract FlashGLPStrategy is FlashStrategyAdmin, ReentrancyGuard {
    using SafeERC20 for IERC20Metadata;

    event BurnedFToken(address indexed _address, uint256 _tokenAmount, uint256 _yieldReturned);

    address immutable flashProtocolAddress;
    address immutable principalTokenAddress;
    address fTokenAddress;

    uint256 principalBalance;

    address immutable stakedGLPTracker = 0x1aDDD80E6039594eE970E5872D247bf0414C8903;
    address public gmxRewardRouterV2 = 0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1;
    address public yieldProcessorAddress;

    constructor(address _flashProtocolAddress, address _principalTokenAddress)
    FlashStrategyAdmin(_principalTokenAddress) {
        flashProtocolAddress = _flashProtocolAddress;
        principalTokenAddress = _principalTokenAddress;
    }

    // @notice Allows Flashstake Protocol to deposit principal tokens
    // @dev this can only be called by the Flashstake Protocol
    function depositPrincipal(uint256 _tokenAmount) external onlyAuthorised returns (uint256) {
        principalBalance += _tokenAmount;

        return _tokenAmount;
    }

    // @notice Allows Flashstake Protocol to withdraw principal tokens
    // @dev this can only be called by the Flashstake Protocol
    function withdrawPrincipal(uint256 _tokenAmount) external onlyAuthorised {
        require(_tokenAmount <= principalBalance, "WITHDRAW TOO HIGH");

        IERC20Metadata(principalTokenAddress).safeTransfer(msg.sender, _tokenAmount);

        principalBalance -= _tokenAmount;
    }

    // @notice retrieve the total principal locked within this strategy
    function getPrincipalBalance() public view returns (uint256) {
        return principalBalance;
    }

    // @notice retrieve the total amount of yield currently in the yield pool
    function getYieldBalance() public view returns (uint256) {
        uint256 totalBalance = IERC20Metadata(stakedGLPTracker).balanceOf(address(this));

        return totalBalance - principalBalance;
    }

    // @notice retrieve the principal token address this strategy accepts
    function getPrincipalAddress() external view returns (address) {
        return principalTokenAddress;
    }

    // @notice retrieve the fToken address associated with this strategy
    function getFTokenAddress() external view returns (address) {
        return fTokenAddress;
    }

    // @notice sets the fToken address
    // @dev this can only be called once when registering the strategy against the Flashstake Protocol
    // @dev this can only be called by the Flashstake Protocol
    function setFTokenAddress(address _fTokenAddress) external onlyAuthorised {
        require(fTokenAddress == address(0), "FTOKEN ADDRESS ALREADY SET");
        fTokenAddress = _fTokenAddress;
    }

    // @notice returns the number of fTokens to mint given some principal and duration
    // @dev this can only be called by anyone
    function quoteMintFToken(uint256 _tokenAmount, uint256 _duration) external pure returns (uint256) {
        // Enforce minimum _duration
        require(_duration >= 60, "DURATION TOO LOW");

        // 1 ERC20 for 365 DAYS = 1 fERC20
        // 1 second = 0.000000031709792000
        // eg (100000000000000000 * (1 second * 31709792000)) / 10**18
        uint256 amountToMint = (_tokenAmount * (_duration * 31709792000)) / (10**18);

        return amountToMint;
    }

    // @notice returns the number (estimate) of principal tokens returned when burning some amount of fTokens
    // @dev this can only be called by anyone with fTokens
    function quoteBurnFToken(uint256 _tokenAmount) public view returns (uint256) {
        uint256 totalSupply = IERC20Metadata(fTokenAddress).totalSupply();
        require(totalSupply > 0, "INSUFFICIENT fERC20 TOKEN SUPPLY");

        if (_tokenAmount > totalSupply) {
            _tokenAmount = totalSupply;
        }

        uint256 totalYield = getYieldBalance();
        return (totalYield * _tokenAmount) / totalSupply;
    }

    // @notice burns fTokens to redeem yield from yield pool
    // @dev this can only be called by anyone with fTokens
    function burnFToken(
        uint256 _tokenAmount,
        uint256 _minimumReturned,
        address _yieldTo
    ) external nonReentrant returns (uint256) {

        uint256 tokensOwed = quoteBurnFToken(_tokenAmount);
        require(tokensOwed >= _minimumReturned, "INSUFFICIENT OUTPUT");

        IFlashFToken(fTokenAddress).burnFrom(msg.sender, _tokenAmount);

        // Check to ensure principal will not be touched (purely protective just in case)
        require(IERC20Metadata(stakedGLPTracker).balanceOf(address(this)) - tokensOwed >= principalBalance);

        IERC20Metadata(principalTokenAddress).safeTransfer(_yieldTo, tokensOwed);

        emit BurnedFToken(msg.sender, _tokenAmount, tokensOwed);

        return tokensOwed;
    }

    modifier onlyAuthorised() {
        require(msg.sender == flashProtocolAddress || msg.sender == address(this), "NOT FLASH PROTOCOL");
        _;
    }

    // @notice claims all underlying yield from GMX:GLP (eg WETH)
    // @dev this can be called by anyone (no reward)
    function claimUnderlyingProtocolYield() public {
        IRewardRouterV2(gmxRewardRouterV2).claim();
    }

    // @notice set the underlying protocol yield contracts for claiming
    // @dev this can only be called by the Owner
    function setGmxRewardRouterV2(address _gmxRewardRouterV2) onlyOwner public {
        gmxRewardRouterV2 = _gmxRewardRouterV2;
    }

    // @notice set the authorised address allowed to call claimAndConvert
    // @dev this can only be called by the Owner
    function setYieldProcessorAddress(address _yieldProcessorAddress) onlyOwner public {
        yieldProcessorAddress = _yieldProcessorAddress;
    }

    // @notice claim and convert GMX:GLP yield
    // @dev this can only be called by the yieldProcessorAddress
    function claimAndConvert(
        address _rewardRouter,
        address _glpManagerAddress,
        address _tokenToConvert,
        uint256 _amountFee,
        uint256 _amountToConvert,
        uint256 _minUsdg,
        uint256 _minGlp
    ) external returns(uint256 _glpMinted) {
        require(msg.sender == yieldProcessorAddress, "!AUTH");

        require(_tokenToConvert != principalTokenAddress &&
            _tokenToConvert != stakedGLPTracker, "TOKEN ADDRESS PROHIBITED");

        claimUnderlyingProtocolYield();

        IERC20Metadata(_tokenToConvert).safeTransfer(msg.sender, _amountFee);

        IERC20Metadata(_tokenToConvert).approve(_glpManagerAddress, _amountToConvert);
        return IRewardRouter(_rewardRouter).mintAndStakeGlp(_tokenToConvert, _amountToConvert, _minUsdg, _minGlp);
    }
}

