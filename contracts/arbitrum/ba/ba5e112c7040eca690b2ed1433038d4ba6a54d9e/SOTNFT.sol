pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./ERC721AQueryable.sol";

contract SOTNFT is Ownable, ERC721AQueryable {
    uint256 public constant MAX_MINT = 25000;
    uint256 public constant MAX_FREE_MINT = 100;
    uint256 public constant MAX_MINT_BY_ADDRESS = 25;
    uint256 public constant PRICE_NFT = 0.0015 ether;

    string private defaultURI;
    address payable public receiver;
    uint256 public totalFreeMinted;

    mapping(address => bool) public isFreeMint;
    mapping(address => uint256) public totalMinted;
    mapping(address => uint256) public totalInvited;
    
    event Mint(address indexed who, address indexed inviter, uint256 indexed quantity);

    constructor(address payable _receiver) ERC721A("Show Off NFT", "SOTNFT") {
        receiver = _receiver;
    }

    function updateBaseURI(string memory _defaultURI) external onlyOwner {
        defaultURI = _defaultURI;
    }

    function freeMint(address _inviter) external {
        address who = _msgSender();
        require(totalSupply() < MAX_MINT, "Max mint");
        require(totalFreeMinted < MAX_FREE_MINT, "Max free mint");
        require(totalMinted[who] < MAX_MINT_BY_ADDRESS, "Limit mint by address");
        require(!isFreeMint[who], "Already mint");

        totalFreeMinted++;
        totalMinted[who]++;
        if (_inviter != address(0)) {
            totalInvited[_inviter] += 1;
        }
        isFreeMint[who] = true;
        _mint(who, 1);
        emit Mint(who, _inviter, 1);
    }

    function mint(address _inviter, uint256 _quantity) external payable {
        address who = _msgSender();
        require(totalSupply() + _quantity <= MAX_MINT, "Max mint");
        require(totalMinted[who] + _quantity <= MAX_MINT_BY_ADDRESS, "Limit mint by address");
        require(msg.value >= PRICE_NFT * _quantity, "Price undervalued");

        totalMinted[who] += _quantity;
        if (_inviter != address(0)) {
            totalInvited[_inviter] += 1;
        }
        receiver.transfer(msg.value);
        _mint(who, _quantity);
        emit Mint(who, _inviter, _quantity);
    }

    function _startTokenId() internal override view virtual returns (uint256) {
        return 1;
    }

    function _baseURI() internal override view virtual returns (string memory) {
        return defaultURI;
    }
}
