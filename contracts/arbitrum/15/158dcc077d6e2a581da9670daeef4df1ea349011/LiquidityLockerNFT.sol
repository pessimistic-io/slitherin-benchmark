// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";
import "./SafeMath.sol";
import "./ReentrancyGuard.sol";
import "./INonfungiblePositionManager.sol";


contract LiquidityLockerNFT is Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    event LockStarted(uint256 lockDuration, uint256 tokenId);

    event FeesCollected(uint256 amount0, uint256 amount1);

    event NftWithdrawed(uint256 tokenId, address to);

    INonfungiblePositionManager public immutable uniswapLpNFT;
    IERC20 public immutable token0;
    IERC20 public immutable token1;
    
    bool public started;
    uint256 public lockDuration;
    uint256 private endingTimestamp;

    modifier lockStarted() {
        require(started, "LiquidityLockerNFT: Not started");
        _;
    }

    modifier lockEnded() {
        require(started && block.timestamp > endingTimestamp, "LiquidityLockerNFT: Not ended");
        _;
    }

    constructor(address _token0, address _token1, address _uniswapLpNFT) {
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
        uniswapLpNFT = INonfungiblePositionManager(_uniswapLpNFT);
    }

    function lock(uint256 _tokenID, uint256 _lockDuration) external onlyOwner {
        require(_lockDuration >= 1 weeks, "LiquidityLockerNFT: Try higher");

        lockDuration = _lockDuration;
        endingTimestamp = block.timestamp.add(_lockDuration);
        started = true;

        uniswapLpNFT.transferFrom(msg.sender, address(this), _tokenID);

        emit LockStarted(_tokenID, lockDuration);
    }

    function collectFees(uint256 tokenID) external onlyOwner lockStarted nonReentrant {
        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams({
            tokenId: tokenID,
            recipient: address(this),
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });

        (uint256 amount0, uint256 amount1) = uniswapLpNFT.collect(params);

        _sendFees(amount0, amount1);

        emit FeesCollected(amount0, amount1);
    }

    function unlock(uint256 tokenID) external onlyOwner lockEnded nonReentrant {
        uniswapLpNFT.transferFrom(address(this), msg.sender, tokenID);

        emit NftWithdrawed(tokenID, msg.sender);
    }
    
    function _sendFees(uint256 amount0, uint256 amount1) internal {
        token0.transfer(msg.sender, amount0);
        token1.transfer(msg.sender, amount1);
    }

}
