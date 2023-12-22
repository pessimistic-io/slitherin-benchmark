pragma solidity ^0.8.17;
import "./Ownable.sol";
import "./IERC20.sol";
import "./ERC20.sol";
import "./IERC721.sol";
import "./ReentrancyGuard.sol";
import "./Utils.sol";

interface IFren {
    function balanceOf(address) external view returns (uint256);

    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256);

    function transfer(address to, uint256 amount) external returns (bool);
}

contract REFUND_TO_FEED_GOAT is Ownable, ReentrancyGuard {
    mapping(address => bool) public _isJeet;
    mapping(address => bool) public _claimed;
    address public USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    uint256 public Alloc = 108000000;

    constructor() public {}

    function setTimeRugVictims(address[] calldata _addresses, bool vitcim) public onlyOwner {
        for (uint256 i = 0; i < _addresses.length; i++) {
            _isJeet[_addresses[i]] = vitcim;
        }
    }

    function claim_GOAT() public nonReentrant returns (uint256) {
        require(_isJeet[msg.sender], "onliJeetz");
        require(!_claimed[msg.sender], "U claimed ur alloc already fren");

        _claimed[msg.sender] = true;
        IFren(USDC).transfer(msg.sender, Alloc);
    }

    function somethingAboutTokens(address token) external onlyOwner {
        uint256 balance = IFren(token).balanceOf(address(this));
        IFren(token).transfer(msg.sender, balance);
    }

    function changeRewardConstants(uint256 _Alloc) external onlyOwner {
        Alloc = _Alloc;
    }
}

