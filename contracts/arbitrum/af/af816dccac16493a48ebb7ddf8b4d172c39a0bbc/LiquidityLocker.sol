// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { ReentrancyGuard }      from "./ReentrancyGuard.sol";
import { IERC721Receiver } from "./IERC721Receiver.sol";
import { Ownable } from "./Ownable.sol";
import { IERC721 } from "./IERC721.sol";

contract LiquidityLocker is Ownable, IERC721Receiver, ReentrancyGuard {

    mapping(uint256 => uint256) public tokenIdUnlockTime;
    uint256 public numberTokensLocked;
    IERC721 public immutable lockToken;

    event TokensLocked(IERC721 lockedToken, uint256 tokenIdAddedToLock, uint256 totalTokensLocked, uint256 unlockTimeStamp);
    event TokensUnlocked(IERC721 lockedToken, uint256 tokenIdRemovedFromLock, uint256 remainingTokensLocked);

    constructor(address _token) {
        lockToken = IERC721(_token);
    }

    function lockTokens(uint256 _tokenId, uint256 _unlockTime) external onlyOwner nonReentrant {
        require(_unlockTime > block.timestamp, "Invalid lock");
        tokenIdUnlockTime[_tokenId] = _unlockTime;
        lockToken.safeTransferFrom(msg.sender, address(this), _tokenId);
        numberTokensLocked++;
        emit TokensLocked(lockToken, _tokenId, numberTokensLocked, _unlockTime);
    }

    function withdrawTokens(uint256 _tokenId) external onlyOwner nonReentrant {
        require(block.timestamp >= tokenIdUnlockTime[_tokenId], "Too soon");

        delete tokenIdUnlockTime[_tokenId];
        lockToken.safeTransferFrom(address(this), msg.sender, _tokenId);
        numberTokensLocked--;
        emit TokensUnlocked(lockToken, _tokenId, numberTokensLocked);
    } 

    function onERC721Received(address, address, uint256, bytes memory) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
