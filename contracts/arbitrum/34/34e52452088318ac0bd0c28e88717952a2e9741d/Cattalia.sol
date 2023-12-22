// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./ERC721Upgradeable.sol";
import "./ERC721EnumerableUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./SafeMath.sol";
import "./SafeERC20.sol";

contract Cattalia is ERC721EnumerableUpgradeable, OwnableUpgradeable {
    using SafeMath for uint256;
    using Address for address payable;

    uint256 public maxIndex;
    uint256 public index;
    uint256 public unitPrice;
    uint256 public endTime;

    event NFTMinted(address _owner, uint256 _id);
    event NFTBurned(uint256 _id);

    function initialize() public initializer {
        __Ownable_init();
        __ERC721_init("Cattalia", "CATTALIA");
        index = 1;
        maxIndex = 6666;
        unitPrice = 1400000000000000; //0.0014 ETH
        endTime = block.timestamp.add(3 days);
    }

    function mint(uint256 quantity) public payable {
        address to = _msgSender();
        require(block.timestamp < endTime, "Expired");
        require(index + quantity < maxIndex, "Max supply");
        uint256 price = unitPrice.mul(quantity);
        require(msg.value >= price, "Insufficient payment");
        for (uint256 i = 0; i < quantity; i++) {
            _mint(to, index + i);
            emit NFTMinted(to, index + i);
        }
        index = index.add(quantity);
    }

    function burn(uint256 tokenId) public {
        require(_ownerOf(tokenId) == _msgSender(), "!Owner");
        _burn(tokenId);
        emit NFTBurned(tokenId);
    }

    function setEndTime(uint256 _endTime) public onlyOwner{
        endTime = _endTime;
    }

    function setMaxIndex(uint256 _maxIndex) public onlyOwner{
        maxIndex = _maxIndex;
    }

    function setUnitPrice(uint256 _unitPrice) public onlyOwner{
        unitPrice = _unitPrice;
    }

    function transferFunds(address payable recipient) public onlyOwner {
        recipient.transfer(address(this).balance);
    }

    /**
        * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
}

