// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./ERC721.sol";
import "./ERC721Enumerable.sol";
import "./Ownable.sol";
import "./Strings.sol";
import "./base64.sol";

interface IMINION {
    function moloch() external view returns (address);

    function avatar() external view returns (address);
}

interface IWrappedETH {
    function deposit() external payable;

    function transfer(address dst, uint256 wad) external returns (bool);
}

contract FomoNFT is ERC721Enumerable, Ownable {
    uint256 public saleTime;
    uint256 public lastMintTime;
    uint256 public startingPrice; // 10**15
    uint256 public price; // Price starts at .001 eth
    address public molochAddr;
    address public avatarAddr;
    address public lastMinter;
    uint256 public nextTokenId = 0;
    string private _baseTokenURI;

    // How long to wait until the last minter can withdraw
    uint256 public withdrawalWaitSeconds; // 3600 * 24 * 3 3 days
    uint256 public numWithdrawals = 0;

    mapping(uint256 => uint256) public withdrawalNums;
    mapping(uint256 => uint256) public withdrawalAmounts;
    mapping(uint256 => string) public _tokenBgs;

    event TokenNameEvent(uint256 tokenId, string newName);
    event MintEvent(
        uint256 indexed tokenId,
        address indexed owner,
        uint256 price
    );
    event WithdrawalEvent(
        uint256 indexed tokenId,
        address destination,
        uint256 amount20,
        uint256 amount80
    );
    event InitEvent(address minion, address avatar, address moloch);

    IMINION public minion;
    IWrappedETH public wrapper;

    constructor(
        address _minion,
        address _wrapper,
        uint256 _saleTime,
        uint256 _withdrawalWaitSeconds,
        uint256 _startingPrice
    ) ERC721("FomoNFT", "FOMO") {
        // requires
        saleTime = _saleTime;
        lastMintTime = saleTime;
        withdrawalWaitSeconds = _withdrawalWaitSeconds;
        startingPrice = _startingPrice;
        price = startingPrice;
        if (_minion == address(0)) {
            avatarAddr = _msgSender();
            molochAddr = _msgSender();
        } else {
            minion = IMINION(_minion);
            avatarAddr = minion.avatar();
            molochAddr = minion.moloch();
        }
        wrapper = IWrappedETH(_wrapper);
        transferOwnership(avatarAddr);
        emit InitEvent(_minion, avatarAddr, molochAddr);
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    function setBaseURI(string memory baseURI) public onlyOwner {
        _baseTokenURI = baseURI;
    }

    function setTokenBg(uint256 id, string memory bgHash) public onlyOwner {
        require(id == numWithdrawals, "Can only change for current round");
        _tokenBgs[id] = bgHash;
    }

    /**
     * If there was no mint for withdrawalWaitSeconds, then the last minter can withdraw
     * 20% goes to last minter, 80% is wraped and goes to the dao
     */
    function withdraw() public {
        require(_msgSender() == lastMinter, "Only last minter can withdraw.");
        require(timeUntilWithdrawal() == 0, "Not enough time has elapsed.");

        address destination = lastMinter;
        // Someone will need to mint again to become the last minter.
        lastMinter = address(0);

        // Token that trigerred the withdrawal
        uint256 tokenId = nextTokenId - 1;
        uint256 amount20 = withdrawalAmount();
        uint256 amount80 = address(this).balance - amount20;

        numWithdrawals += 1;
        withdrawalAmounts[tokenId] = amount20;

        (bool success20, ) = destination.call{value: amount20}("");
        require(success20, "Transfer failed.");

        // wrap eth
        wrapper.deposit{value: amount80}();
        // send to dao
        require(
            wrapper.transfer(molochAddr, amount80),
            "WrapNZap: transfer failed"
        );

        // reset price to .001 eth and start over
        price = startingPrice;

        emit WithdrawalEvent(tokenId, destination, amount20, amount80);
    }

    /**
     * Mint fee is split
     * 20% goes to the dao minion
     * 80% to the dao minion
     */
    function mint() public payable {
        uint256 newPrice = getMintPrice();
        require(
            msg.value >= newPrice,
            "The value submitted with this transaction is too low."
        );
        require(block.timestamp >= saleTime, "The sale is not open yet.");

        lastMinter = _msgSender();
        lastMintTime = block.timestamp;

        price = newPrice;
        uint256 molochCut = price / 5;
        uint256 tokenId = nextTokenId;
        nextTokenId += 1;
        withdrawalNums[tokenId] = numWithdrawals;

        _safeMint(lastMinter, tokenId);

        // transfer cut to minion
        (bool success1, ) = avatarAddr.call{value: molochCut}("");
        require(success1, "Transfer failed.");

        if (msg.value > price) {
            // Return the extra money to the minter.
            (bool success2, ) = lastMinter.call{
                value: msg.value - price - molochCut
            }("");
            require(success2, "Transfer failed.");
        }

        emit MintEvent(tokenId, lastMinter, price);
    }

    function getMintPrice() public view returns (uint256) {
        return (price * 10188) / 10000;
    }

    function timeUntilSale() public view returns (uint256) {
        if (saleTime < block.timestamp) return 0;
        return saleTime - block.timestamp;
    }

    function timeUntilWithdrawal() public view returns (uint256) {
        uint256 withdrawalTime = lastMintTime + withdrawalWaitSeconds;
        if (withdrawalTime < block.timestamp) return 0;
        return withdrawalTime - block.timestamp;
    }

    function withdrawalAmount() public view returns (uint256) {
        return address(this).balance / 5;
    }

    // Returns a list of token Ids owned by _owner.
    function walletOfOwner(address _owner)
        public
        view
        returns (uint256[] memory)
    {
        uint256 tokenCount = balanceOf(_owner);

        if (tokenCount == 0) {
            // Return an empty array
            return new uint256[](0);
        }

        uint256[] memory result = new uint256[](tokenCount);
        for (uint256 i; i < tokenCount; i++) {
            result[i] = tokenOfOwnerByIndex(_owner, i);
        }
        return result;
    }

    /**  Constructs the tokenURI, separated out from the public function as its a big function.
     * Generates the json data URI and svg data URI that ends up sent when someone requests the tokenURI
     * svg has a image tag that can be updated by the owner (dao)
     * param: _tokenId the tokenId
     */
    function _constructTokenURI(uint256 _tokenId)
        internal
        view
        returns (string memory)
    {
        string memory _nftName = string(abi.encodePacked("FomoNFT DAO "));
        string memory _metadataSVGs = string(
            abi.encodePacked(
                '<image width="100%" href="',
                _baseTokenURI,
                _tokenBgs[withdrawalNums[_tokenId]],
                '" />',
                '<text dominant-baseline="middle" text-anchor="middle" fill="white" x="50%" y="40%">FOMO NFT DAO</text>',
                '<text dominant-baseline="middle" text-anchor="middle" fill="white" x="50%" y="50%">',
                Strings.toString(withdrawalNums[_tokenId]),
                " - ",
                Strings.toString(_tokenId),
                "</text>"
            )
        );

        bytes memory svg = abi.encodePacked(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 400" preserveAspectRatio="xMidYMid meet" style="font:14px serif"><rect width="400" height="400" fill="black" />',
            _metadataSVGs,
            "</svg>"
        );

        bytes memory _image = abi.encodePacked(
            "data:image/svg+xml;base64,",
            Base64.encode(bytes(svg))
        );

        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    Base64.encode(
                        bytes(
                            abi.encodePacked(
                                '{"name":"',
                                _nftName,
                                '", "image":"',
                                _image,
                                // Todo something clever
                                '", "description": "You got a golden ticket"}'
                            )
                        )
                    )
                )
            );
    }

    /* Returns the json data associated with this token ID
     * param _tokenId the token ID
     */
    function tokenURI(uint256 _tokenId)
        public
        view
        override
        returns (string memory)
    {
        require(
            _exists(_tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );
        return string(_constructTokenURI(_tokenId));
    }
}

