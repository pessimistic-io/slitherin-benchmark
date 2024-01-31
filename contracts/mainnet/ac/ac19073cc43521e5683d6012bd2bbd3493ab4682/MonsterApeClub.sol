// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC721.sol";
import "./ERC721Enumerable.sol";
import "./ECDSA.sol";
import "./SafeMath.sol";
import "./Strings.sol";
import "./Ownable.sol";

/**
 * @title Monster Ape Club contract.
 * @notice Extends openzeppelin ERC721 implementation.
 */
contract MonsterApeClub is ERC721Enumerable, Ownable {
    using SafeMath for uint256;

    uint256 public price;
    uint256 public start;
    uint256 public end;
    uint256 public totalLimit;
    uint256 public mintLimit;
    uint256 public batchLimit;
    address root;
    string baseTokenURI;
    bool public publicSale = false;

    mapping(address => uint256) public purchased;

    constructor() ERC721("Monster Ape Club", "MAC") {}

    /**
     * @notice Initialize sale parameters
     *
     * @param _price a mint price per token
     * @param _start mint start timestamp
     * @param _end mint end timestamp
     * @param _totalLimit tokens available, considering those reserved for the airdrops
     * @param _mintLimit tokens available to purchase
     * @param _batchLimit tokens available to purchase per wallet
     * @param _root signer address for verification with
     * @param _baseTokenURI base metadata url
     */
    function initialize(uint256 _price, uint256 _start, uint256 _end, uint256 _totalLimit, uint256 _mintLimit, uint256 _batchLimit, address _root, string memory _baseTokenURI) public onlyOwner {
        price = _price;
        start = _start;
        end = _end;
        totalLimit = _totalLimit;
        mintLimit = _mintLimit;
        batchLimit = _batchLimit;
        root = _root;
        baseTokenURI = _baseTokenURI;
    }

    /**
     * @notice Mints specific amount of apes to the address
     *
     * @param _start mint start timestamp
     * @param _end mint end timestamp
     * @param _amount tokens to mint
     * @param _signature signed message confirming access to the mint
     */
    function buy(uint256 _start, uint256 _end, uint256 _amount, bytes memory _signature) public payable {
        uint256 supply = totalSupply();

        address signer = ECDSA.recover(keccak256(abi.encode(_start, _end, _amount)), _signature);
        require(signer == root, "Not authorized to mint");
        require(block.timestamp >= start, "Sale not started yet");
        require(block.timestamp <= end, "Sale ended");
        require((_amount + purchased[msg.sender]) <= batchLimit, "Each address can only purchase up to 2 apes");
        require(supply.add(_amount) <= mintLimit, "Purchase would exceed apes supply");
        require(price.mul(_amount) <= msg.value, "Apes price is not correct");

        uint256 i;

        for (i = 0; i < _amount; i++) {
            if (supply + i < mintLimit) {
                _safeMint(msg.sender, supply + i);
            }
        }

        purchased[msg.sender] += i;
    }

    /**
     * @notice Mints specific amount of apes to the address, skipping the verification (will be enabled in case presale won't exceed the mint limit)
     *
     * @param _amount tokens to mint
     */
    function buyPublic(uint256 _amount) public payable {
        uint256 supply = totalSupply();

        require(publicSale == true, "Public sale is not active");
        require((_amount + purchased[msg.sender]) <= batchLimit, "Each address can only purchase up to 2 apes");
        require(supply.add(_amount) <= mintLimit, "Purchase would exceed apes supply");
        require(price.mul(_amount) <= msg.value, "Apes price is not correct");

        uint256 i;

        for (i = 0; i < _amount; i++) {
            if (supply + i < mintLimit) {
                _safeMint(msg.sender, supply + i);
            }
        }

        purchased[msg.sender] += i;
    }

    /**
     * @notice Airdrops apes to the address
     * Can only be called by the current owner
     *
     * @param _amount tokens to airdrop
     * @param _recipient wallet to airdrop to
     */
    function airdrop(uint256 _amount, address _recipient) public onlyOwner {
        uint256 supply = totalSupply();

        require(supply.add(_amount) <= totalLimit, "Airdrop would exceed apes supply");

        for (uint256 i = 0; i < _amount; i++) {
            if (supply + i < totalLimit) {
                _safeMint(_recipient, supply + i);
            }
        }
    }

    /**
     * @notice Flips the public sale state
     * Can only be called by the current owner
     */
    function flipPublicSaleState() public onlyOwner {
        publicSale = !publicSale;
    }

    /**
     * @notice Returns token metadata URI
     *
     * @param _tokenId desired token id to see the metadata for
     */
    function tokenURI(uint256 _tokenId) override public view returns (string memory) {
        return string(abi.encodePacked(baseTokenURI, Strings.toString(_tokenId)));
    }

    /**
     * @notice Withdraw specific amount from the balance
     * Can only be called by the current owner
     */
    function withdraw(address payable _to, uint256 _amount) public onlyOwner {
        _to.transfer(_amount);
    }

    /**
     * Declaring fallback and recieve functions when using "payable" keyword in contract, since it is neccessary since solidity 0.6.0
     */
    fallback() external payable {}

    receive() external payable {}
}

