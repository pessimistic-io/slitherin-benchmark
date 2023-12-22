// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

import "./ReentrancyGuard.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";
import "./IERC721.sol";
import "./SafeERC20.sol";

interface IDefiEdgeStrategy {
  function mint(
    uint256 amount0, uint256 amount1, uint256 amount0Min, uint256 amount1Min, uint256 minShare
  ) external returns (uint256 amount0_, uint256 amount1_, uint256 shares);
}

interface IWETH {
  function deposit() external payable;

  function transfer(address to, uint value) external returns (bool);

  function withdraw(uint) external;
}

interface INFTPOOL is IERC721 {
  function getPoolInfo() external view returns (
    address lpToken, address grailToken, address sbtToken, uint256 lastRewardTime, uint256 accRewardsPerShare,
    uint256 lpSupply, uint256 lpSupplyWithMultiplier, uint256 allocPoint
  );

  function getStakingPosition(uint256 tokenId) external view returns (
    uint256 amount, uint256 amountWithMultiplier, uint256 startLockTime,
    uint256 lockDuration, uint256 lockMultiplier, uint256 rewardDebt,
    uint256 boostPoints, uint256 totalMultiplier
  );

  function lastTokenId() external view returns (uint256);

  function createPosition(uint256 amount, uint256 lockDuration) external;
}

contract DefiEdgeProxyHelper is Ownable, ReentrancyGuard {
  using SafeERC20 for IERC20;
  using SafeMath for uint256;

  bytes4 private constant _ERC721_RECEIVED = 0x150b7a02;
  uint256 private expectedTokenId;
  address private expectedNftPool;

  address public constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;


  receive() external payable {
    assert(msg.sender == WETH);
  }

  function onERC721Received(address /*operator*/, address from, uint256 tokenId, bytes calldata /*data*/) external view returns (bytes4){
    require(tokenId == expectedTokenId && msg.sender == expectedNftPool && from == address(0), "Invalid tokenId");
    return _ERC721_RECEIVED;
  }

  function depositETH(
    IERC20 token0, IERC20 token1, uint256 deposit0, uint256 deposit1, uint256 deposit0Min, uint256 deposit1Min,
    uint256 minShare, address strategy, INFTPOOL nftPool, uint256 lockDuration
  ) external payable nonReentrant {
    require(address(token0) == WETH || address(token1) == WETH, "non ETH deposit");

    (address nftUnderlyingAsset,,,,,,,) = nftPool.getPoolInfo();
    require(strategy == nftUnderlyingAsset, "invalid nftPool");

    uint256 ethAmount = address(token0) == WETH ? deposit0 : deposit1;
    IWETH(WETH).deposit{value : ethAmount}();
    if (address(token0) == WETH) token1.safeTransferFrom(msg.sender, address(this), deposit1);
    else token0.safeTransferFrom(msg.sender, address(this), deposit0);

    _deposit(token0, token1, deposit0, deposit1, deposit0Min, deposit1Min, minShare, strategy, nftPool, lockDuration);

    // refund unused token
    uint256 token0Balance = token0.balanceOf(address(this));
    if (token0Balance > 0) address(token0) == WETH ? IWETH(WETH).withdraw(token0Balance) : token0.safeTransfer(msg.sender, token0Balance);

    uint256 token1Balance = token1.balanceOf(address(this));
    if (token1Balance > 0) address(token1) == WETH ? IWETH(WETH).withdraw(token1Balance) : token1.safeTransfer(msg.sender, token1Balance);

    if (address(this).balance > 0) safeTransferETH(msg.sender, address(this).balance);
  }

  function deposit(
    IERC20 token0, IERC20 token1, uint256 deposit0, uint256 deposit1, uint256 deposit0Min, uint256 deposit1Min,
    uint256 minShare, address strategy, INFTPOOL nftPool, uint256 lockDuration
  ) external nonReentrant {
    (address nftUnderlyingAsset,,,,,,,) = nftPool.getPoolInfo();
    require(strategy == nftUnderlyingAsset, "invalid nftPool");

    token1.safeTransferFrom(msg.sender, address(this), deposit1);
    token0.safeTransferFrom(msg.sender, address(this), deposit0);

    _deposit(token0, token1, deposit0, deposit1, deposit0Min, deposit1Min, minShare, strategy, nftPool, lockDuration);

    // refund unused tokens
    uint256 token0Balance = token0.balanceOf(address(this));
    if (token0Balance > 0) token0.safeTransfer(msg.sender, token0Balance);

    uint256 token1Balance = token1.balanceOf(address(this));
    if (token1Balance > 0) token1.safeTransfer(msg.sender, token1Balance);
  }

  function _deposit(
    IERC20 token0, IERC20 token1, uint256 deposit0, uint256 deposit1, uint256 deposit0Min, uint256 deposit1Min,
    uint256 minShare, address strategy, INFTPOOL nftPool, uint256 lockDuration
  ) internal {
    token0.safeApprove(strategy, 0);
    token0.safeApprove(strategy, deposit0);
    token1.safeApprove(strategy, 0);
    token1.safeApprove(strategy, deposit1);
    (,, uint256 shares) = IDefiEdgeStrategy(strategy).mint(deposit0, deposit1, deposit0Min, deposit1Min, minShare);

    expectedTokenId = nftPool.lastTokenId().add(1);
    expectedNftPool = address(nftPool);

    IERC20(strategy).safeApprove(expectedNftPool, 0);
    IERC20(strategy).safeApprove(expectedNftPool, shares);
    nftPool.createPosition(shares, lockDuration);

    (uint256 shares_,,,uint256 lockDuration_,,,,) = nftPool.getStakingPosition(expectedTokenId);
    require(shares == shares_ && lockDuration == lockDuration_, "invalid position created");
    nftPool.safeTransferFrom(address(this), msg.sender, expectedTokenId);

    expectedTokenId = 0;
    expectedNftPool = address(0);
  }

  function rescueERC20(address token, uint256 amount) external onlyOwner {
    IERC20(token).safeTransfer(owner(), amount);
  }

  function safeTransferETH(address to, uint256 value) internal {
    (bool success,) = to.call{value : value}(new bytes(0));
    require(success, 'safeTransferETH: ETH transfer failed');
  }
}
