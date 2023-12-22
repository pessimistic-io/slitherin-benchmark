// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @author Brewlabs
 * This contract has been developed by brewlabs.info
 */
import {Ownable} from "./Ownable.sol";
import {SafeERC20, IERC20} from "./SafeERC20.sol";
import {ERC721, ERC721Enumerable, IERC721} from "./ERC721Enumerable.sol";
import {Strings} from "./Strings.sol";
import {DefaultOperatorFilterer} from "./DefaultOperatorFilterer.sol";

contract TrueApex is Ownable, ERC721Enumerable, DefaultOperatorFilterer {
    using SafeERC20 for IERC20;
    using Strings for uint256;

    uint256 private constant MAX_SUPPLY = 1100;
    bool public mintAllowed = false;

    string private _tokenBaseURI = "";
    mapping(uint256 => string) private _tokenURIs;

    uint256 private premine = 100;
    uint256 public mintPrice = 2000 * 10 ** 6;
    IERC20 public feeToken = IERC20(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);
    address public feeWallet;
    uint256 public oneTimeMintLimit = 10;

    uint256 private numAvailableItems = 1100;
    uint256[1100] private availableItems;

    mapping(address => uint256) public whitelisted;

    event MintEnabled();
    event Mint(address indexed user, uint256 tokenId);
    event BaseURIUpdated(string uri);

    event SetFeeToken(address token);
    event SetMintPrice(uint256 price);
    event SetOneTimeMintLimit(uint256 limit);

    event SetFeeWallet(address wallet);

    event SetWhitelist(address addr, uint256 num);
    event RemoveWhitelist(address addr);

    constructor() ERC721("TrueApex NFT Collection", "TrueX") {
        feeWallet = msg.sender;
    }

    function setApprovalForAll(address operator, bool approved)
        public
        override(ERC721, IERC721)
        onlyAllowedOperatorApproval(operator)
    {
        super.setApprovalForAll(operator, approved);
    }

    function approve(address operator, uint256 tokenId)
        public
        override(ERC721, IERC721)
        onlyAllowedOperatorApproval(operator)
    {
        super.approve(operator, tokenId);
    }

    function transferFrom(address from, address to, uint256 tokenId)
        public
        override(ERC721, IERC721)
        onlyAllowedOperator(from)
    {
        super.transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId)
        public
        override(ERC721, IERC721)
        onlyAllowedOperator(from)
    {
        super.safeTransferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data)
        public
        override(ERC721, IERC721)
        onlyAllowedOperator(from)
    {
        super.safeTransferFrom(from, to, tokenId, data);
    }

    function preMint(address _to, uint256 _numToMint) external onlyOwner {
        require(totalSupply() < premine, "Premine already finished");

        for (uint256 i = 0; i < _numToMint; i++) {
            if (totalSupply() >= premine) break;

            uint256 tokenId = _randomAvailableTokenId(_numToMint, i);
            numAvailableItems--;

            _safeMint(_to, tokenId);
            _setTokenURI(tokenId, tokenId.toString());

            emit Mint(_to, tokenId);
        }
    }

    function mint(uint256 _numToMint) external {
        require(_numToMint > 0, "Invalid amount");
        require(_numToMint <= oneTimeMintLimit, "Exceed one-time mint limit");
        require(totalSupply() + _numToMint <= MAX_SUPPLY, "Cannot exceed supply");

        uint256 count = _numToMint;
        if (whitelisted[msg.sender] >= _numToMint) {
            whitelisted[msg.sender] -= _numToMint;
        } else {
            if (mintAllowed) {
                feeToken.safeTransferFrom(msg.sender, feeWallet, mintPrice * (_numToMint - whitelisted[msg.sender]));
            } else {
                count = whitelisted[msg.sender];
            }
            whitelisted[msg.sender] = 0;
        }
        require(count > 0, "Cannot mint now");

        for (uint256 i = 0; i < count; i++) {
            uint256 tokenId = _randomAvailableTokenId(count, i);
            numAvailableItems--;

            _safeMint(msg.sender, tokenId);
            _setTokenURI(tokenId, tokenId.toString());

            emit Mint(msg.sender, tokenId);
        }

        if (totalSupply() == MAX_SUPPLY) mintAllowed = false;
    }

    function _randomAvailableTokenId(uint256 _numToFetch, uint256 _i) internal returns (uint256) {
        uint256 randomNum = uint256(
            keccak256(
                abi.encode(
                    msg.sender, tx.gasprice, block.number, block.timestamp, blockhash(block.number - 1), _numToFetch, _i
                )
            )
        );

        uint256 randomIndex = randomNum % numAvailableItems;

        uint256 valAtIndex = availableItems[randomIndex];
        uint256 result;
        if (valAtIndex == 0) {
            // This means the index itself is still an available token
            result = randomIndex;
        } else {
            // This means the index itself is not an available token, but the val at that index is.
            result = valAtIndex;
        }

        uint256 lastIndex = numAvailableItems - 1;
        if (randomIndex != lastIndex) {
            // Replace the value at randomIndex, now that it's been used.
            // Replace it with the data from the last index in the array, since we are going to decrease the array size afterwards.
            uint256 lastValInArray = availableItems[lastIndex];
            if (lastValInArray == 0) {
                // This means the index itself is still an available token
                availableItems[randomIndex] = lastIndex;
            } else {
                // This means the index itself is not an available token, but the val at that index is.
                availableItems[randomIndex] = lastValInArray;
            }
        }

        return result;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "URI query for nonexistent token");

        string memory _tokenURI = _tokenURIs[tokenId];
        string memory base = _baseURI();

        // If there is no base URI, return the token URI.
        if (bytes(base).length == 0) {
            return _tokenURI;
        }
        // If both are set, concatenate the baseURI and tokenURI (via abi.encodePacked).
        if (bytes(_tokenURI).length > 0) {
            return string(abi.encodePacked(base, _tokenURI));
        }

        return super.tokenURI(tokenId);
    }

    function enableMint() external onlyOwner {
        require(totalSupply() == premine, "Premine is not processed yet");
        require(!mintAllowed, "Already enabled");
        require(totalSupply() < MAX_SUPPLY, "Mint was finished");
        mintAllowed = true;
        emit MintEnabled();
    }

    function setMintPrice(uint256 _price) external onlyOwner {
        mintPrice = _price;
        emit SetMintPrice(mintPrice);
    }

    function setFeeToken(address _token) external onlyOwner {
        require(_token != address(0x0), "Invalid token");
        require(_token != address(feeToken), "Already set");
        require(!mintAllowed, "Mint was enabled");

        feeToken = IERC20(_token);
        emit SetFeeToken(_token);
    }

    function setTokenBaseUri(string memory _uri) external onlyOwner {
        _tokenBaseURI = _uri;
        emit BaseURIUpdated(_uri);
    }

    function setOneTimeMintLimit(uint256 _limit) external onlyOwner {
        require(_limit <= 50, "Cannot exceed 50");
        oneTimeMintLimit = _limit;
        emit SetOneTimeMintLimit(_limit);
    }

    function setAdminWallet(address _wallet) external onlyOwner {
        require(_wallet != address(0x0), "Invalid address");
        feeWallet = _wallet;
        emit SetFeeWallet(_wallet);
    }

    function addToWhitelist(address _addr, uint256 _amount) external onlyOwner {
        require(_addr != address(0x0), "Invalid address");
        whitelisted[_addr] = _amount;
        emit SetWhitelist(_addr, _amount);
    }

    function removeFromWhitelist(address _addr) external onlyOwner {
        require(_addr != address(0x0), "Invalid address");
        whitelisted[_addr] = 0;
        emit RemoveWhitelist(_addr);
    }

    function _baseURI() internal view override returns (string memory) {
        return _tokenBaseURI;
    }

    function _setTokenURI(uint256 tokenId, string memory _tokenURI) internal {
        require(_exists(tokenId), "URI set of nonexistent token");
        _tokenURIs[tokenId] = _tokenURI;
    }

    receive() external payable {}
}

