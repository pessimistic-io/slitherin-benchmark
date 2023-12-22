// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

//import ERC721holderupgradable
import "./ERC721HolderUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./IERC20MetadataUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";

interface IAIGF {
    function mint(string memory uri, address addr) external;

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

    function ownerOf(uint256 tokenId) external view returns (address owner);

    function balanceOf(address addr) external view returns (uint);
}


interface IERC20Metadata {

    function decimals() external view returns (uint8);
}

contract AIGF_Minter is OwnableUpgradeable, ERC721HolderUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    IAIGF public aigf;
    IERC20Upgradeable public RIZZ;
    uint public mintPrice;


    struct UserInfo {
        uint mintAmount;
        bool isWhite;
        bool isMinted;
    }

    mapping(address => UserInfo) public userInfo;
    IERC20Upgradeable public token;

    struct TimeInfo {
        uint firstMintTime;
        uint firstMintEndTime;
        uint secondMintTime;
        uint secondMintEndTime;
    }

    TimeInfo public timeInfo;
    address public wallet;
    address[] mintList;
    mapping(address => bool) public isAirdrop;

    event Bond(address indexed invitor, address indexed user);
    event Mint(address indexed user, string indexed uri);


    function initialize() public initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();
        mintPrice = 100e18;
        wallet = address(this);

    }

    modifier onlyEOA(){
        require(msg.sender == tx.origin, "onlyEOA");
        _;
    }


    function setMintPrice(uint _price) public onlyOwner {
        mintPrice = _price;
    }

    function setWallet(address _wallet) public onlyOwner {
        wallet = _wallet;
    }


    function setAIGF(address _aigf) public onlyOwner {
        aigf = IAIGF(_aigf);
    }

    function setRIZZ(address rizz_) public onlyOwner {
        RIZZ = IERC20Upgradeable(rizz_);
    }

    function setAIGFToken(address token_) public onlyOwner {
        token = IERC20Upgradeable(token_);
    }


    function setTimeInfo(uint _firstMintTime, uint _firstMintEndTime, uint _secondMintTime, uint _secondMintEndTime) public onlyOwner {
        timeInfo.firstMintTime = _firstMintTime;
        timeInfo.firstMintEndTime = _firstMintEndTime;
        timeInfo.secondMintTime = _secondMintTime;
        timeInfo.secondMintEndTime = _secondMintEndTime;
    }


    function setWhite(address[] memory addrs, bool b) external onlyOwner {
        for (uint i = 0; i < addrs.length; i++) {
            userInfo[addrs[i]].isWhite = b;
        }
    }


    function mintAIGF(string memory uri) external onlyEOA {
        //        require(!userInfo[msg.sender].isMinted, "minted");
        uint timeNow = block.timestamp;
        require(timeNow >= timeInfo.firstMintTime, "mintAIGF: not in first mint time");
        require(timeNow < timeInfo.secondMintEndTime, 'end');
        if (timeNow < timeInfo.firstMintEndTime) {
            require(userInfo[msg.sender].mintAmount == 0, "mintAIGF: minted");
            require(mintList.length < 1000, 'out of limit');
            mintList.push(msg.sender);
            isAirdrop[msg.sender] = true;
        }
        userInfo[msg.sender].mintAmount++;

        if (timeNow >= timeInfo.secondMintTime) {
            RIZZ.transferFrom(msg.sender, wallet, mintPrice);

        }
        userInfo[msg.sender].isMinted = true;
        aigf.mint(uri, msg.sender);
        emit Mint(msg.sender, uri);
    }

    function checkMintList() public view returns (address[] memory) {
        return mintList;
    }


    function safePull(address token_, address wallet_, uint amount_) external onlyOwner {
        IERC20Upgradeable(token_).transfer(wallet_, amount_);
    }

}
