//Contract based on [https://docs.openzeppelin.com/contracts/3.x/erc721](https://docs.openzeppelin.com/contracts/3.x/erc721)
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC721.sol";
import "./Counters.sol";
import "./Ownable.sol";
import "./ERC721URIStorage.sol";
import "./Strings.sol";
import "./Address.sol";

import "./console.sol";
contract Punknpunks is ERC721URIStorage, Ownable {
    using Strings for uint256;
    using Address for address;
    using Counters for Counters.Counter;
    Counters.Counter private _tokenCount; //make private.

    string public nftBaseURI;  //URI + /pnp
    uint256[] public minted;

    uint256 public constant NFT_PRICE = 10000000000000000; // 0.01 ETH
    uint256 public constant MAX_SUPPLY = 10000;

    // Variables for game
    address[] public participants;
    address public winner;
    uint256 public payoutInterval = 200;
    uint256 private Funds = 0;
    uint256 public Pool = 0;

    bool public saleIsActive = false;  // set to false on deployment.
    bool private payout = false;

    constructor() ERC721("Punknpunks", "PNP") {}

    function flipSaleState() public onlyOwner {
        saleIsActive = !saleIsActive;
    }

    // Will withdrawl all the money in the event there are funds left over after all 10,000 are minted.
    function withdrawAll() public onlyOwner {
        uint256 balance = address(this).balance;
        payable(msg.sender).transfer(balance);
    }

    // Withdraw only from rationed funds.
    function withdraw() public onlyOwner {
        payable(msg.sender).transfer(Funds);
        Funds = 0;
    }

    function mintNFT(address recipient, uint256 pnpId) public payable returns (uint256) {
        require(saleIsActive);
        require(pnpId < MAX_SUPPLY);
        require(NFT_PRICE == msg.value);

        Funds = Funds + 8000000000000000; // 0.008 ETH
        Pool = Pool + 2000000000000000; // 0.002 ETH

        enterPlayer(recipient);

        if (_tokenCount.current() % payoutInterval == 0 && _tokenCount.current() > 0) {
            payout = true;
            payOutPool();
            payout = false;
        }

        string memory tokenURI = buildTokenURI(pnpId);
        _safeMint(recipient, pnpId);
        _setTokenURI(pnpId, tokenURI);

        _tokenCount.increment();
        minted.push(pnpId);

        return pnpId;
    }

    event Payout(address winner);

    // Handles lottery payment function.
    function payOutPool() private {
        require(payout);
        winner = participants[random() % participants.length];
        payable(winner).transfer(Pool);  // Send funds to winner.
        emit Payout(winner);
        // Cleanup.
        Pool = 0;
        participants = new address payable[](0);
    }

    // Enter someone into the game.
    function enterPlayer(address recipient) private {
        participants.push(recipient);
    }

    // Sets the base uri for nft.
    function setBaseURI(string memory nftBaseURI_) public onlyOwner {
        nftBaseURI = nftBaseURI_;
    }

    // Generates token uri and adjusts for meta data name.
    function buildTokenURI(uint256 pnpId_) public view returns (string memory) {
        return string(abi.encodePacked(nftBaseURI, pnpId_.toString()));
    }

    // Generates random number.
    function random() public view returns (uint){  // TODO: Change to private.
        return uint(keccak256(abi.encodePacked(block.difficulty, block.timestamp, participants)));
    }

    function totalMinted() public view returns (uint256) {
        return(_tokenCount.current());
    }

    function mintedTokenIds() public view returns (uint256[] memory) {
        return minted;
    }
}
