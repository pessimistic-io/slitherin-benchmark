// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "./ERC721.sol";
import "./ERC721Enumerable.sol";
import "./SafeMath.sol";
import "./Ownable.sol";
import "./Address.sol";
import "./ReentrancyGuard.sol";


//  Contract: NoTooPunks.sol
                                                                                                
//  Author: NotooPunks.eth
//  Website: NoTooPunks.eth.link


//  . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . .01001110
//  . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . .
//  . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . .01101111
//  . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . .
//  . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . .01010100
//  . . . . . . . . @ @ @ @ @ @ @ . . . . . . . . . . . . . . . . . .
//  . . . . . . . @ o o o o o o o @ . . . . . . . . . . . . . . . . .01101111
//  . . . . . . @ o o ~ o o o o o o @ . . . . . . . . . . . . . . . .
//  . . . . . . @ o ~ o o o o o o o @ . . . . . . . . . . . . . . . .
//  . . . . . . @ o o o o o o o o o @ . . . . . . . . . . . . . . . .01101111
//  . . . . . . @ o o o o o o o o o @ . . . . . . . . . . . . . . . .
//  . . . . . . @ o o x x o o o x x @ . . . . . . . . . . . . . . . .
//  . . . . . @ o o o ^ @ o o o ^ @ @ . . . . . . . . . . . . . . . .01010000
//  . . . . . @ o o o x o o o o x o @ . . . . . . . . . . . . . . . .
//  . . . . . @ @ o o o o o o o o o @ . . . . . . . . . . . . . . . .
//  . . . . . . @ o o o o o @ @ o o @ . . . . . . . . . . . . . . . .01110101
//  . . . . . . @ o o o o o o o o o @ . . . . . . . . . . . . . . . .
//  . . . . . . @ o o o o o o o o o @ . . . . . . . . . . . . . . . .
//  . . . . . . @ o o o o @ @ @ o o @ . . . . . . . . . . . . . . . .01101110
//  . . . . . . @ o o o o x o o o o @ . . . . . . . . . . . . . . . .
//  . . . . . . @ o o o o o o o o @ . . . . . . . . . . . . . . . . .01101011
//  . . . . . . @ o o o @ @ @ @ @ . . . . . . . . . . . . . . . . . .
//  . . . . . . @ o o o @ . . . . . . . . . . . . . . . . . . . . . .01110011
//  . . . . . . @ o o o @ . . . . . . . . . . . . . . . . . . . . . .
//  ███    ██  ██████      ████████  ██████   ██████      ██████  ██    ██ ███    ██ ██   ██ ███████ 
//  ████   ██ ██    ██        ██    ██    ██ ██    ██     ██   ██ ██    ██ ████   ██ ██  ██  ██      
//  ██ ██  ██ ██    ██        ██    ██    ██ ██    ██     ██████  ██    ██ ██ ██  ██ █████   ███████ 
//  ██  ██ ██ ██    ██        ██    ██    ██ ██    ██     ██      ██    ██ ██  ██ ██ ██  ██       ██ 
//  ██   ████  ██████         ██     ██████   ██████      ██       ██████  ██   ████ ██   ██ ███████ 
                                                                                                 
                                                                                            
contract NoTooPunksV3 is ERC721, ERC721Enumerable, Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    // ----- Token config -----
    // Total number of NoTooPunks that can be minted
    uint256 public constant maxSupply = 10000;
    // Number of NoTooPunks reserved for promotion & giveaways
    uint256 public totalReserved = 100;
    // IPFS hash of the 100x100 grid of the NoTooPunks
    // You can use this hash to verify the image file containing all the punks
    string public NTP_PROVENANCE_SHA256 = "6f6c9f62838dc13db2c72379863d1fe364b168039041cbea7a01ccbbb49c4328";

    // Root of the IPFS metadata store
    string public baseURI = "";
    // Current number of tokens
    uint256 public numTokens = 0;
    // remaining NoTooPunks in the reserve
    uint256 private _reserved;

    // ----- Sale config -----
    // Price for a single token
    uint256 private _price = 0.04 ether;
    // Can you mint tokens already
    bool private _saleStarted;

    // ----- Owner config -----
    address public punkDev1 = 0xb630DBd03e975A1a3e9fa174e3C7F7AaF1AFe6E2;
    address public punkDev2 = 0xe3Da74aAD302A70147deDB7835111DA5DFEb1C0a;
    address public dao = 0x51e31f532c054505A01D786dfaFDA1aCA2Fee40C;

    // Mapping which token we already handed out
    uint256[maxSupply] private indices;

    // Constructor. We set the symbol and name and start with sa
    constructor(
    ) ERC721("NoTooPunks",  unicode"₱") {
        _saleStarted = false;
        _reserved = totalReserved;
    }

    receive() external payable {}

    // ----- Modifiers config -----
    // restrict to only allow when we have a running sale
    modifier saleIsOpen() {
        require(_saleStarted == true, "Sale not started yet");
        _;
    }

    // restrict to onyl accept requests from one either deployer, punkDev1 or punkDev2
    modifier onlyAdmin() {
        require(
            _msgSender() == owner() || _msgSender() == punkDev1 || _msgSender() == punkDev2,
            "Ownable: caller is not admin"
        );
        _;
    }

    // ----- ERC721 functions -----
    function _baseURI() internal view override(ERC721) returns (string memory) {
        return baseURI;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    // ----- Getter functions -----
    function getPrice() public view returns (uint256) {
        return _price;
    }

    function getReservedLeft() public view returns (uint256) {
        return _reserved;
    }

    function getSaleStarted() public view returns (bool) {
        return _saleStarted;
    }

    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }

    // ----- Setter functions -----
    // These functions allow us to change values after contract deployment


    // Way to change the baseUri, this is usefull if we ever need to switch the IPFS gateway for example
    function setBaseURI(string memory _URI) external onlyOwner {
        baseURI = _URI;
    }

    // ----- Minting functions -----

    /// @notice Select a random number without modulo bias using a random seed and upper bound
    /// @param _entropy The seed for randomness
    /// @param _upperBound The upper bound of the desired number
    /// @return A random number less than the _upperBound
    function uniform(uint256 _entropy, uint256 _upperBound)
        internal
        pure
        returns (uint256)
    {
        require(_upperBound > 0, "UpperBound needs to be >0");
        uint256 negation = _upperBound & (~_upperBound + 1);
        uint256 min = negation % _upperBound;
        uint256 randomNr = _entropy;
        while (true) {
            if (randomNr >= min) {
                break;
            }
            randomNr = uint256(keccak256(abi.encodePacked(randomNr)));
        }
        return randomNr % _upperBound;
    }

    /// @notice Generates a pseudo random number based on arguments with decent entropy
    /// @param max The maximum value we want to receive
    /// @return _randomNumber A random number less than the max
    function random(uint256 max) internal view returns (uint256 _randomNumber) {
        uint256 randomness = uint256(
            keccak256(
                abi.encode(
                    msg.sender,
                    tx.gasprice,
                    block.number,
                    block.timestamp,
                    blockhash(block.number - 1),
                    block.difficulty
                )
            )
        );
        _randomNumber = uniform(randomness, max);
        return _randomNumber;
    }

    /// @notice Generates a pseudo random index of our tokens that has not been used so far
    /// @return A random index between 0 and 9999
    function randomIndex() internal returns (uint256) {
        // id of the gerneated token
        uint256 tokenId = 0;
        //  number of tokens left to create
        uint256 totalSize = maxSupply - numTokens;
        // generate a random index
        uint256 index = random(totalSize);
        // if we haven't handed out a token with nr index we that now

        uint256 tokenAtPlace = indices[index];

        // if we havent stored a replacement token...
        if (tokenAtPlace == 0) {
            //... we just return the current index
            tokenId = index;
        } else {
            // else we take the replace we stored with logic below
            tokenId = tokenAtPlace;
        }

        // get the highest token id we havent handed out
        uint256 lastTokenAvailable = indices[totalSize - 1];
        // we need to store a replacement token for the next time we roll the same index
        // if the last token is still unused...
        if (lastTokenAvailable == 0) {
            // ... we store the last token as index
            indices[index] = totalSize - 1;
        } else {
            // ... we store the token that was stored for the last token
            indices[index] = lastTokenAvailable;
        }

        // We start our tokens at 0
        return tokenId;
    }

    /// @notice Select a number of tokens and send them to a receiver
    /// @param _number How many tokens to mint
    /// @param _receiver Address to mint the tokens to
    function _internalMint(uint256 _number, address _receiver)
        internal
    {
        for (uint256 i; i < _number; i++) {
            uint256 tokenID = randomIndex();
            numTokens = numTokens + 1;
            _safeMint(_receiver, tokenID);
        }
    }

    /// @notice Mint a number of tokens and send them to a receiver
    /// @param _number How many tokens to mint
    function mint(uint256 _number)
        external
        payable
        nonReentrant
        saleIsOpen
    {
        uint256 supply = uint256(totalSupply());
        require(
            supply + _number <= maxSupply - _reserved,
            "Not enough NoTooPunks left."
        );
        require(
            _number < 21,
            "You cannot mint more than 20 NoTooPunks at once!"
        );
        require(_number * _price == msg.value, "Inconsistent amount sent!");
        _internalMint(_number, msg.sender);
    }

    // ----- Sale functions -----

    /// @notice Flip the sale status
    function flipSaleStarted() external onlyAdmin {
        _saleStarted = !_saleStarted;
    }

    // ----- Helper functions -----
    /// @notice Get all token ids belonging to an address
    /// @param _owner Wallet to find tokens of
    /// @return  Array of the owned token ids
    function walletOfOwner(address _owner)
        public
        view
        returns (uint256[] memory)
    {
        uint256 tokenCount = balanceOf(_owner);

        uint256[] memory tokensId = new uint256[](tokenCount);
        for (uint256 i; i < tokenCount; i++) {
            tokensId[i] = tokenOfOwnerByIndex(_owner, i);
        }
        return tokensId;
    }

    /// @notice Claim a number of tokens from the reserve for free
    /// @param _number How many tokens to mint
    /// @param _receiver Address to mint the tokens to
    function claimReserved(uint256 _number, address _receiver)
        external
        onlyAdmin
    {
        require(_number <= _reserved, "That would exceed the max reserved.");
        _internalMint(_number, _receiver);
        _reserved -= _number;
    }

    /// @notice his will take the eth on the contract and split it based on the logif below and send it out.  We funnel 1/3 for each dev and 1/3 into the NoTooPunksDAO
    function withdraw() public onlyAdmin {
        uint256 _balance = address(this).balance;
        uint256 _split = _balance.mul(33).div(100);
        require(payable(punkDev1).send(_split));
        require(payable(punkDev2).send(_split));
        require(payable(dao).send(_balance.sub(_split * 2)));
    }
}
