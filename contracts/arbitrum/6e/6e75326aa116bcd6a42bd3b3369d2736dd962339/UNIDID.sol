pragma solidity ^0.8.4;

import "./Ownable.sol";
import "./IERC20.sol";
import "./ERC721.sol";
import "./Counters.sol";
import "./StringUtils.sol";
import "./SafeMath.sol";

contract UNIDID is Ownable, ERC721 {
    using StringUtils for *;
    using Strings for uint256;
    using SafeMath for uint256;
    string private baseUrl = '';
    address minter;

    uint256 public amount = 1 * 1e14;
    uint256 private fee = 100;
    mapping(address => bool) public feeFlag;

    mapping(uint256 => bool) public regStateMap;
    mapping(uint256 => bytes32) public nftIdMap;

    constructor() ERC721("Unified DID Pass", "UNIDID") {
        minter = msg.sender;
    }

    event DidReg(string name, address to, uint256 tokenId);
    event Born(uint256 tokenId);

    function mint(address to, string memory name) public onlyMinter returns (uint256)
    {
        require(valid(name), 'the name length error');

        bytes32 fullId = genId(name);
        uint256 newItemId = uint256(fullId);

        require(!regStateMap[newItemId], 'the  domian has registered');

        regStateMap[newItemId] = true;
        nftIdMap[newItemId] = fullId;
        _mint(to, newItemId);
        emit DidReg(name, to, newItemId);

        feeFlag[to] = false;
        return newItemId;
    }

    function genId(string memory name) public view returns (bytes32) {
        bytes32 fullId = keccak256(bytes(name));
        return fullId;
    }

    function isPayFee(address user) public view returns (bool) {
        return feeFlag[user];
    }

    function available(string memory name) public view returns (bool) {
        if(!valid(name))return false;
        bytes32 fullId = genId(name);
        uint256 newItemId = uint256(fullId);
        return !regStateMap[newItemId];
    }

    function burn(uint256 tokenId) public{
        _burn(tokenId);
        regStateMap[tokenId] = false;
        nftIdMap[tokenId] = 0;
        emit Born(tokenId);
    }

    function valid(string memory name) public pure returns(bool) {
        return name.strlen() >= 3;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return baseUrl;
    }

    function setBaseurl(string memory url_) public onlyOwner{
        baseUrl = url_;
    }


    event onFee(address user);
    function sendFee() payable public  {
        require(msg.value >= amount, 'send plant coin is err');
        payable(minter).transfer(amount.mul(fee).div(100));
        emit onFee(msg.sender);
        feeFlag[msg.sender] = true;
    }

    function setAmount(uint256 _amount) public onlyOwner{
        amount = _amount;
    }

    function setFee(uint256 _amount) public onlyOwner{
        fee = _amount;
    }

    modifier onlyMinter() {
        require(minter == _msgSender(), "Ownable: caller is not the minter");
        _;
    }
}



