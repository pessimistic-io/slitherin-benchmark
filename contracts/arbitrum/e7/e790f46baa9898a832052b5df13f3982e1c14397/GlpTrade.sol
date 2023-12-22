// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

import "./IERC20.sol";
import "./AccessControl.sol";
import "./Ownable.sol";

interface IRewardRouterV2 {
  function mintAndStakeGlp(address _token, uint256 _amount, uint256 _minUsdg, uint256 _minGlp) external returns (uint256);
  function unstakeAndRedeemGlp(address _tokenOut, uint256 _glpAmount, uint256 _minOut, address _receiver) external returns (uint256);
}

interface IGlpManager {
  function getAum(bool maximise) external view returns (uint256);
}

interface IGlpVault {
    function deposit(uint256 assets, address receiver) external returns (uint256);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256);
}

contract GlpTrade is AccessControl, Ownable {

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    address private feeWallet;
    uint256 public fee; //in bips

    IERC20 public constant GLP = IERC20(0x1aDDD80E6039594eE970E5872D247bf0414C8903); // Fee + Staked GLP (fsGLP)
    IERC20 public constant SGLP = IERC20(0x2F546AD4eDD93B956C8999Be404cdCAFde3E89AE);
    IRewardRouterV2 public constant GlpRewardRouterV2 = IRewardRouterV2(0xB95DB5B167D75e6d04227CfFFA61069348d271F5);
    IGlpManager public constant GLPManager = IGlpManager(0x3963FfC9dff443c2A94f21b129D429891E32ec18);
    IGlpVault public vault = IGlpVault(0xfF6b69B78DF465bf7e55D242fD11456158D1600A);

    struct allowedToken {
        string tokenName;
        address tokenAddress;
        uint decimals;
        bool isAllowed;
    }

    uint allowedTokenIndex;
    mapping(uint => allowedToken) public allowedTokensList;

    event GlpPurchased(address user, IERC20 token, uint256 tokenAmount, uint256 glpAmount);
    event GlpDepositedToVault(address user, uint256 assets, uint256 shares);

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function setTokenToAllowlist(string memory _tokenName, address _tokenAddress, uint _decimals) external onlyOwner {
        allowedTokensList[allowedTokenIndex] = allowedToken(_tokenName, _tokenAddress, _decimals, true);
        allowedTokenIndex+=1;
    }

    function removeTokenFromAllowlist(uint _allowedTokenId) external onlyRole(ADMIN_ROLE) {
        allowedTokensList[_allowedTokenId].isAllowed = false;
    }

    function setFee(uint256 _fee) external onlyRole(ADMIN_ROLE) {
        fee = _fee;
    }

    function setFeeWallet(address _feeWallet) external onlyOwner {
        feeWallet = _feeWallet;
    }

    function setVault(address _vaultAddress) external onlyOwner {
        vault = IGlpVault(_vaultAddress);
    }

    function buyGlpAndSentToVault(uint _allowedTokenId, uint256 _amount, uint256 _minGlpToBuy) public {
        require(allowedTokensList[_allowedTokenId].isAllowed, "Not an allowed token");
        IERC20 token = IERC20(allowedTokensList[_allowedTokenId].tokenAddress);
        require(token.allowance(msg.sender, address(this)) >= _amount,"Insufficient Allowance");
        require(token.balanceOf(msg.sender) >= _amount,"Insufficient Balance in user wallet");
        token.transferFrom(msg.sender, address(this), _amount);
        token.approve(address(GLPManager), _amount);
        uint256 amountPurchased = GlpRewardRouterV2.mintAndStakeGlp(
        allowedTokensList[_allowedTokenId].tokenAddress, // token to buy GLP with
        _amount,             // amount of token to use for the purchase
        0,   // the minimum acceptable USD value of the GLP purchased
        _minGlpToBuy   // the minimum acceptable GLP amount
        );

        emit GlpPurchased(msg.sender, token, _amount, amountPurchased);

        SGLP.approve(address(vault), amountPurchased);
        uint256 shares = vault.deposit(amountPurchased, msg.sender);
        emit GlpDepositedToVault(msg.sender, amountPurchased, shares);
    }


   // function redeemGlpFromVaultAndWithdraw() public {
   // }

}

