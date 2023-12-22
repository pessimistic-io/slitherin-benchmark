// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import "./IERC20.sol";
import "./AccessControl.sol";
import "./Ownable.sol";

interface IRewardRouterV2 {
  function mintAndStakeGlp(address _token, uint256 _amount, uint256 _minUsdg, uint256 _minGlp) external returns (uint256);
  function unstakeAndRedeemGlp(address _tokenOut, uint256 _glpAmount, uint256 _minOut, address _receiver) external returns (uint256);
}

interface IGlpVault is IERC20 {
    function deposit(uint256 assets, address receiver) external returns (uint256);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256);
}

contract GLPDeposit is AccessControl, Ownable {

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant WHITELISTED_ROLE = keccak256("WHITELISTED_ROLE");

    IERC20 public constant GLP = IERC20(0x1aDDD80E6039594eE970E5872D247bf0414C8903); // Fee + Staked GLP (fsGLP)
    IERC20 public constant SGLP = IERC20(0x2F546AD4eDD93B956C8999Be404cdCAFde3E89AE);
    IRewardRouterV2 public glpRewardRouterV2 = IRewardRouterV2(0xB95DB5B167D75e6d04227CfFFA61069348d271F5);
    address public GLPManager = 0x3963FfC9dff443c2A94f21b129D429891E32ec18;
    IGlpVault public vault;

    struct allowedToken {
        string tokenName;
        address tokenAddress;
        uint decimals;
        bool isAllowed;
    }

    uint allowedTokenIndex;
    mapping(uint => allowedToken) public allowedTokensList;

    event GlpPurchased(address user, IERC20 token, uint256 tokenAmount, uint256 glpAmount);
    event GlpSold(address user, IERC20 token, uint256 tokenAmount, uint256 glpAmount);
    event GlpDepositedToVault(address user, uint256 assets, uint256 shares);
    event GlpRedeemedFromVault(address user, uint256 shares, uint256 assets);

    uint256 slippage = 1;

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // list of tokens allowed to buy GLP
    function setTokenToAllowlist(string memory _tokenName, address _tokenAddress, uint _decimals) external onlyRole(ADMIN_ROLE) {
        allowedTokensList[allowedTokenIndex] = allowedToken(_tokenName, _tokenAddress, _decimals, true);
        allowedTokenIndex+=1;
    }

    function removeTokenFromAllowlist(uint _allowedTokenId) external onlyRole(ADMIN_ROLE) {
        allowedTokensList[_allowedTokenId].isAllowed = false;
    }

    function setVault(address _vaultAddress) external onlyRole(ADMIN_ROLE) {
        vault = IGlpVault(_vaultAddress);
    }

    function setGlpRewardRouter(address _newAddress) public onlyRole(ADMIN_ROLE) {
        glpRewardRouterV2 = IRewardRouterV2(_newAddress);
    }

    function setGLPManager(address _newAddress) external onlyRole(ADMIN_ROLE) {
        GLPManager = _newAddress;
    }

    function setSlippage(uint256 _slippage) external onlyRole(ADMIN_ROLE) {
        slippage = _slippage;
    }

    function buyGlpAndSentToVault(uint _tokenId, uint256 _amount, uint256 _minGlpToBuy) external onlyRole(WHITELISTED_ROLE) {
        require(allowedTokensList[_tokenId].isAllowed, "Not an allowed token");
        IERC20 token = IERC20(allowedTokensList[_tokenId].tokenAddress);
        require(token.allowance(msg.sender, address(this)) >= _amount,"Insufficient Allowance");
        require(token.balanceOf(msg.sender) >= _amount,"Insufficient Balance in user wallet");
        token.transferFrom(msg.sender, address(this), _amount);
        token.approve(GLPManager, _amount);
        uint256 amountPurchased = glpRewardRouterV2.mintAndStakeGlp(
        allowedTokensList[_tokenId].tokenAddress, // token to buy GLP with
        _amount,             // amount of token to use for the purchase
        0,   // the minimum acceptable USD value of the GLP purchased
        _minGlpToBuy   // the minimum acceptable GLP amount
        );

        emit GlpPurchased(msg.sender, token, _amount, amountPurchased);

        SGLP.approve(address(vault), amountPurchased);
        uint256 shares = vault.deposit(amountPurchased, msg.sender);
        emit GlpDepositedToVault(msg.sender, amountPurchased, shares);
    }


   function redeemGlpFromVaultAndWithdraw(uint _tokenId, uint256 _shares) external onlyRole(WHITELISTED_ROLE) {
        require(allowedTokensList[_tokenId].isAllowed, "Not an allowed token");
        IERC20 token = IERC20(allowedTokensList[_tokenId].tokenAddress);
        require(vault.allowance(msg.sender, address(this)) >= _shares,"Insufficient Allowance");
        require(vault.balanceOf(msg.sender) >= _shares,"Insufficient Balance in user wallet");
        vault.transferFrom(msg.sender, address(this), _shares);

        uint256 assets = vault.redeem(_shares, address(this), address(this));
        emit GlpRedeemedFromVault(msg.sender, _shares, assets);

        uint256 amountReceived = glpRewardRouterV2.unstakeAndRedeemGlp(
           allowedTokensList[_tokenId].tokenAddress,
           assets,
           0, 
           msg.sender
       );

        emit GlpSold(msg.sender, token, amountReceived, assets);
   }

}

