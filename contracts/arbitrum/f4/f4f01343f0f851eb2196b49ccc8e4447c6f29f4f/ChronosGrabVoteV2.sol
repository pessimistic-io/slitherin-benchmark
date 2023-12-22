// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.17;
import "./ChronosBribe.sol";
import "./Voter.sol";
import "./IERC20.sol";
import "./IERC721.sol";

contract ChronosGrabVoteV2 {
    uint256 constant MAX_PAIRS = 60;
    Voter constant voter = Voter(0xC72b5C6D2C33063E89a50B2F77C99193aE6cEe6c);
    IERC721 constant veNFT = IERC721(0x9A01857f33aa382b1d5bb96C3180347862432B0d);
    address private _owner;
    address private _pendingOwner;
    constructor() {
        _owner = msg.sender;
    }

    function rug(address _token) public {
        require(msg.sender == _owner);
        if(_token != address(0)) {
            IERC20 token = IERC20(_token);
            uint256 balance = token.balanceOf(address(this));
            token.transfer(_owner, balance);
            emit Rug(_token, balance);
        } else {
            uint256 balance = address(this).balance;
            (bool succ,) = payable(_owner).call{value: balance}("");
            require(succ);
            emit Rug(address(0), balance);
        }
    }

    function owner() public view returns (address) {
        return _owner;
    }

    function pendingOwner() public view virtual returns (address) {
        return _pendingOwner;
    }

    function transferOwnership(address newOwner) public {
        require(msg.sender == _owner);
        _pendingOwner = newOwner;
        emit OwnershipTransferStarted(_owner, newOwner);
    }

    function acceptOwnership() public {
        require(msg.sender == _pendingOwner);
        emit OwnershipTransferred(_owner, _pendingOwner);
        _owner = _pendingOwner;
        delete _pendingOwner;
    }

    function renounceOwnership() public {
        require(msg.sender == _owner);
        require(_pendingOwner == address(0));
        emit OwnershipTransferred(_owner, address(0));
        delete _owner;
    }

    receive() external payable {
        uint256 tokenId = msg.value;
        address nftOwner = veNFT.ownerOf(tokenId);
        uint256 count;
        address[] memory bribes = new address[](MAX_PAIRS);
        while (true) {
            try voter.poolVote(tokenId, count) returns (address current) {
                address gauge = voter.gauges(current);
                //console.log("gauge address: ", gauge);
                bribes[2*count] = voter.internal_bribes(gauge);
                //console.log("internal bribe: ", internalBribes[count]);
                bribes[2*count+1] = voter.external_bribes(gauge);
                //console.log("external bribe: ", externalBribes[count]);
                unchecked {
                    ++count;
                }
            } catch {
                break;
            }
        }
        assembly ("memory-safe") {
            let dealloc := shl(5, sub(MAX_PAIRS, count))
            let ptr := mload(0x40)
            mstore(bribes, count)
            mstore(0x40, sub(ptr, dealloc))
        }
        address[][] memory bribeRewards = new address[][](count);
        for(uint256 i = 0; i < count;) {
            Bribe bribe = Bribe(bribes[i]);
            uint256 length = bribe.rewardsListLength();
            uint256 actualLength = 0;
            address[] memory tokenList = new address[](length);
            for(uint256 j; j < length;) {
                address reward = bribe.rewardTokens(j);
                if(IERC20(reward).balanceOf(address(bribe)) > 0) {
                    tokenList[j] = reward;
                    unchecked {
                        ++actualLength;
                    }
                }
                unchecked {
                    ++j;
                }
            }
            assembly ("memory-safe") {
                let dealloc := shl(5, sub(length, actualLength))
                let ptr := mload(0x40)
                mstore(tokenList, actualLength)
                mstore(0x40, sub(ptr, dealloc))
            }
            bribeRewards[i] = tokenList;
            unchecked {
                ++i;
            }
        }

        voter.claimBribes(bribes, bribeRewards, tokenId);
        //console.log(tokenCount);
        (bool succ,) = payable(nftOwner).call{value: msg.value}("");
        require(succ);
    }
    // error
    error TooManyToken();
    // event
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event Rug(address indexed tokenAddress, uint256 balance);
}

