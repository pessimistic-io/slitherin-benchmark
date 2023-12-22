// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./IMetaX.sol";
import "./ERC20_IERC20.sol";
import "./AccessControl.sol";
import "./Ownable.sol";
import "./MerkleProof.sol";

contract EarlyBirdUser is AccessControl, Ownable {

/** Roles **/
    bytes32 public constant Admin = keccak256("Admin");

    constructor() {  
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(Admin, msg.sender);
    }

/** Smart Contracts Preset **/
    /* MetaX */
    address public MetaX_Addr;

    IERC20 public MX;

    function setMetaX (address _MetaX_Addr) public onlyOwner {
        MetaX_Addr = _MetaX_Addr;
        MX = IERC20(_MetaX_Addr);
    }

    /* XPower of PlanetMan */
    address public PlanetMan_XPower;

    IMetaX public PM;

    function setPlanetMan(address _PlanetMan_XPower) public onlyOwner {
        PlanetMan_XPower = _PlanetMan_XPower;
        PM = IMetaX(_PlanetMan_XPower);
    }

    /* POSW */
    address public POSW_Addr;

    IMetaX public POSW;

    function setPOSW(address _POSW_Addr) public onlyOwner {
        POSW_Addr = _POSW_Addr;
        POSW = IMetaX(_POSW_Addr);
    }

    /* Excess Claimable User */
    address public ExcessClaimableUser;

    IMetaX public ECU;

    function setExcessClaimableUser(address _ExcessClaimableUser) public onlyOwner {
        ExcessClaimableUser = _ExcessClaimableUser;
        ECU = IMetaX(_ExcessClaimableUser);
    }

/** Claiming Rules **/
    function Rarity (uint256 _tokenId) public pure returns (uint256 rarity) {
        require(_tokenId != 0 && _tokenId <= 10000, "SocialMining: Token not exist.");
        if (0<_tokenId && _tokenId<=50) {
            rarity = 4;
        } else if (50<_tokenId && _tokenId<=500) {
            rarity = 3;
        } else if (500<_tokenId && _tokenId<=2000) {
            rarity = 2;
        } else if (2000<_tokenId && _tokenId<=7000) {
            rarity = 1;
        } else if (7000<_tokenId && _tokenId<=10000) {
            rarity = 0;
        }
    }

    uint256 public beginTime = 1693526400; /* 2023/09/01 00:00 UTC */

    uint256 public deadline_Ini = 1696118400; /* 2023/09/30 24:00 UTC */

    uint256 public deadline_Claim = 1735689600; /* 2024/12/31 24:00 UTC */

/** Early Bird Initialization **/
    /* Verify - Initialization */
    bytes32 public merkleRoot_Ini;

    function setRoot_Ini (bytes32 _merkleRoot_Ini) external onlyRole(Admin) {
        merkleRoot_Ini = _merkleRoot_Ini;
    }

    function flattenArray(uint256[][] memory data) internal pure returns (uint256[] memory) {
        uint256 size = 0;
        for (uint256 i = 0; i < data.length; i++) {
            size += data[i].length;
        }
        uint256[] memory flatArray = new uint256[](size);
        uint256 index = 0;
        for (uint256 i = 0; i < data.length; i++) {
            for (uint256 j = 0; j < data[i].length; j++) {
                flatArray[index] = data[i][j];
                index++;
            }
        }
        return flatArray;
    }

    function verify_Ini (
        uint256 _tokenId_PM,
        uint256 EarlyBirdTokens,
        uint256 EarlyBirdExcess,
        uint256 EarlyBirdPOSW,
        uint256[] memory Id_SocialPlatform,
        uint256[] memory Id_Community,
        uint256[] memory POSW_SocialPlatform,
        uint256[] memory POSW_Community,
        uint256[][] memory POSW_SocialPlatform_Community,
        bytes32[] calldata merkleProof
    ) public view returns (bool) {
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, _tokenId_PM, EarlyBirdTokens, EarlyBirdExcess, EarlyBirdPOSW, Id_SocialPlatform, Id_Community, POSW_SocialPlatform, POSW_Community, flattenArray(POSW_SocialPlatform_Community)));
        return MerkleProof.verify(merkleProof, merkleRoot_Ini, leaf);
    }

    /* Early Bird Recording */
    struct _EarlyBirdToken {
        uint256 tokenId_PM;
        uint256 tokenMax;
        uint256 tokenClaimed;
        uint256 intervals;
        uint256 recentClaimed;
        uint256 maxClaimed;
        uint256 numberClaimed;
    }

    mapping (address => _EarlyBirdToken) public EarlyBirdToken;

    uint256[] public maxClaimed = [40, 24, 14, 8, 4]; /* Common-40 weeks | Uncommon-24 weeks | Rare-14 weeks | Epic-8 weeks | Legendary-4 weeks */

    uint256 public Intervals = 7 days;

    /* Initialize Early Bird */
    mapping (uint256 => bool) public PMalreadyInitialized;

    uint256 public extraTokens = 1090410948 ether; /* Early Bird start from Feb 14th 2023 */

    function Initialize (
        uint256 _tokenId_PM,
        uint256 EarlyBirdTokens,
        uint256 EarlyBirdExcess,
        uint256 EarlyBirdPOSW,
        uint256[] memory Id_SocialPlatform,
        uint256[] memory Id_Community,
        uint256[] memory POSW_SocialPlatform,
        uint256[] memory POSW_Community,
        uint256[][] memory POSW_SocialPlatform_Community,
        bytes32[] calldata merkleProof
    ) public {
        require(block.timestamp >= beginTime && block.timestamp <= deadline_Ini, "Early Bird: Initialization needs to be finished within Sept 2023.");
        require(!PMalreadyInitialized[_tokenId_PM], "Early Bird: Your PlanetMan has already initialized.");
        require(EarlyBirdToken[msg.sender].tokenId_PM == 0, "Early Bird: Your wallet has already initialized.");
        require(verify_Ini(_tokenId_PM, EarlyBirdTokens, EarlyBirdExcess, EarlyBirdPOSW, Id_SocialPlatform, Id_Community, POSW_SocialPlatform, POSW_Community, POSW_SocialPlatform_Community, merkleProof), "Early Bird: Incorrect Early Bird rewards.");
        uint256 totalExcess = EarlyBirdExcess + ECU.getExcess(msg.sender);
        ECU.setExcess(msg.sender, totalExcess);
        POSW.addPOSW_User(msg.sender, EarlyBirdPOSW, Id_SocialPlatform, Id_Community, POSW_SocialPlatform, POSW_Community, POSW_SocialPlatform_Community);
        PM.addPOSW_PM(_tokenId_PM, EarlyBirdPOSW);
        PMalreadyInitialized[_tokenId_PM] = true;
        EarlyBirdToken[msg.sender] = _EarlyBirdToken(_tokenId_PM, EarlyBirdTokens, 0, 7 days, 0, maxClaimed[Rarity(_tokenId_PM)], 0);
        extraTokens -= EarlyBirdTokens;
    }

/** Early Bird Claim **/
    /* Verify Claim */
    bytes32 public merkleRoot_Claim;

    function setRoot_Claim (bytes32 _merkleRoot_Claim) external onlyRole(Admin) {
        merkleRoot_Claim = _merkleRoot_Claim;
    }

    function verify_Claim (uint256 _tokenId_PM, bytes32[] calldata merkleProof) public view returns (bool) {
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, _tokenId_PM));
        return MerkleProof.verify(merkleProof, merkleRoot_Claim, leaf);
    }

    /* Claim */
    function Claim_User (uint256 _tokenId_PM, bytes32[] calldata merkleProof) public {
        uint256 tokens = EarlyBirdToken[msg.sender].tokenMax / EarlyBirdToken[msg.sender].maxClaimed;
        require(block.timestamp < deadline_Claim, "Early Bird: Claiming period is over.");
        require(verify_Claim(_tokenId_PM, merkleProof), "Early Bird: You are not the owner of this PlanetMan NFT.");
        require(EarlyBirdToken[msg.sender].tokenId_PM == _tokenId_PM, "Early Bird: You need to claim your entire early bird rewards with your original PlanetMan NFT.");
        require(block.timestamp >= EarlyBirdToken[msg.sender].recentClaimed + EarlyBirdToken[msg.sender].intervals, "Early Bird User: Please wait for next release.");
        require(EarlyBirdToken[msg.sender].tokenClaimed + tokens <= EarlyBirdToken[msg.sender].tokenMax, "Early Bird User: You have claimed all your early bird tokens.");
        require(EarlyBirdToken[msg.sender].numberClaimed < EarlyBirdToken[msg.sender].maxClaimed, "Early Bird User: You have claimed all your early bird tokens.");
        MX.transfer(msg.sender, tokens);
        EarlyBirdToken[msg.sender].tokenClaimed += tokens;
        EarlyBirdToken[msg.sender].numberClaimed ++;
        EarlyBirdToken[msg.sender].recentClaimed = block.timestamp;
        emit EarlyBirdRecord(msg.sender, _tokenId_PM, tokens, block.timestamp);
    }

    event EarlyBirdRecord(address user, uint256 _tokenId, uint256 tokens, uint256 time);

/** Burn Extra **/
    bool public alreadyBurnt;

    function burnExtra () public onlyOwner {
        require(!alreadyBurnt, "Early Bird: The extra tokens have already been burnt.");
        require(block.timestamp > deadline_Ini, "Early Bird: Initialization period is not over.");
        IMetaX(MetaX_Addr).Burn(address(this), extraTokens);
        alreadyBurnt = true;
    }

    function burnRemaining () public onlyOwner {
        require(block.timestamp > deadline_Claim, "Early Bird: Claiming period is not over.");
        IMetaX(MetaX_Addr).Burn(address(this), MX.balanceOf(address(this)));
    }
}
