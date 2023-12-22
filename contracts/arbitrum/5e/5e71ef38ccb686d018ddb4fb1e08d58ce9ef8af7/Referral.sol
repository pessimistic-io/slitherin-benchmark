// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./IReferral.sol";

contract Referral is OwnableUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;
    uint256 public constant BASIS_DIVISOR = 10000;
    IERC20 public LP;
    IERC20 public esLION;

    mapping(address => bool) public isHandler;
    uint public lastBlockCnt;

    mapping(bytes32 => address) private codeOwners;
    mapping(address => User) private addrToUsers;
    mapping(address=>uint256) public  parentLevel;
    //lp reward claim info
    mapping(address=>mapping(uint256=>uint256)) public  userLPClaimTotal;
    mapping(address=>mapping(uint256=>uint256)) public  userLPClaimed;
    //esLion reward claim info
    mapping(address=>mapping(uint256=>uint256)) public  userESLionClaimTotal;
    mapping(address=>mapping(uint256=>uint256)) public  userESLionClaimed;

    uint[] public levelTradeFeeRewardRate;
    uint[] public levelInviteFeeRewardRate;

    struct User {
        bytes32 code;
        address parent;
        address[] child;
    }

    event SetHandler(address handler, bool isActive);
    event Register(address sender, address owner, bytes32 code);
    event BindParent(address sender, address owner, address parentAddr);
    event Claim(address user, address token, uint256 amount, uint256 total);

    modifier onlyHandler() {
        require(isHandler[msg.sender], "ReferralStorage: forbidden");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(){
        _disableInitializers();
    }

    function _authorizeUpgrade(address newImplementation) internal onlyOwner override {}

    function initialize(
        address _lpToken,
        address _esLionToken
    ) initializer public {
        __Ownable_init();
        lastBlockCnt = block.timestamp;
        levelTradeFeeRewardRate.push(0);
        levelTradeFeeRewardRate.push(500);
        levelTradeFeeRewardRate.push(1000);
        levelTradeFeeRewardRate.push(1250);
        LP = IERC20(_lpToken);
        esLION = IERC20(_esLionToken);
    }

    function setHandler(address _handler, bool _isActive) external onlyOwner {
        isHandler[_handler] = _isActive;
        emit SetHandler(_handler, _isActive);
    }

    function setLevelTradeFeeRewardRate(uint[] memory _levelTradeFeeRewardRate) external onlyOwner {
        levelTradeFeeRewardRate = _levelTradeFeeRewardRate;
    }

    function setLevelInviteFeeRewardRate(uint[] memory _levelInviteFeeRewardRate) external onlyOwner {
        levelInviteFeeRewardRate = _levelInviteFeeRewardRate;
    }

    function setTraderReferralCode(address _account, bytes32 _code) external onlyHandler {
        if (!isRegister(_account)) {
            _registerReferralCode(_account);
        }
        if (addrToUsers[_account].parent == address(0)) {
            _bindReferralCode(_account, _code);
        }
    }

    function register(bytes32 parentCode) public {
        _registerReferralCode(msg.sender);
        if (uint(parentCode) != 0) {
            _bindReferralCode(msg.sender, parentCode);
        }
    }

    function bindReferralCode(bytes32 parentCode) public {
        if (!isRegister(msg.sender)) {
            _registerReferralCode(msg.sender);
        }
        _bindReferralCode(msg.sender, parentCode);
    }

    function claim(uint256 _type) external{
        require(userLPClaimTotal[msg.sender][_type] > userLPClaimed[msg.sender][_type] || userESLionClaimTotal[msg.sender][_type] > userESLionClaimed[msg.sender][_type],'claimed');
        if(userLPClaimTotal[msg.sender][_type] > userLPClaimed[msg.sender][_type]){
            uint256 lpCanClaim = userLPClaimTotal[msg.sender][_type] - userLPClaimed[msg.sender][_type];
            userLPClaimed[msg.sender][_type] += lpCanClaim;
            LP.safeTransfer(msg.sender,lpCanClaim);
        }
        if(userESLionClaimTotal[msg.sender][_type] > userESLionClaimed[msg.sender][_type]){
            uint256 esLionCanClaim = userESLionClaimTotal[msg.sender][_type] - userESLionClaimed[msg.sender][_type];
            userESLionClaimed[msg.sender][_type] += esLionCanClaim;
            esLION.safeTransfer(msg.sender,esLionCanClaim);
        }
    }

    function _registerReferralCode(address owner) internal {
        require(!isRegister(owner), 'registered');

        bytes32 userCode = genCodeBytes32();
        codeOwners[userCode] = owner;
        addrToUsers[owner].code = userCode;

        emit Register(msg.sender, owner, userCode);
    }

    function _bindReferralCode(address owner, bytes32 parentCode) internal {
        require(uint(parentCode) != 0, "Referral: invalid code");
        address parentUser = codeOwners[parentCode];
        require(parentUser != address(0), "Referral: code already not exists");
        require(parentUser != owner && addrToUsers[parentUser].parent != owner, "Referral: invalid code");
        require(addrToUsers[owner].parent == address(0), "Referral: parent exists");

        addrToUsers[owner].parent = parentUser;
        addrToUsers[parentUser].child.push(owner);
        if(parentLevel[parentUser] == 0){
            parentLevel[parentUser] = 1;
        }
        emit BindParent(msg.sender, owner, parentUser);
    }

    function updateLPClaimReward(address _owner,address _parent, uint256 _ownerReward, uint256 _parentReward) external onlyHandler{
        userLPClaimTotal[_owner][0] += _ownerReward;
        userLPClaimTotal[_parent][1] += _parentReward;
    }
    function updateESLionClaimReward(address _owner,address _parent, uint256 _ownerReward, uint256 _parentReward) external onlyHandler{
        userESLionClaimTotal[_owner][0] += _ownerReward;
        userESLionClaimTotal[_parent][1] += _parentReward;
    }

    function updateParentLevel(address[] memory _addrs,uint256[] memory _levels) external onlyHandler{
        require(_addrs.length == _levels.length,"len not same");
        for (uint i = 0; i < _addrs.length; i++) {
            parentLevel[_addrs[i]] = _levels[i];
        }
    }
    function isRegister(address userAddr) view public returns (bool result){
        result = uint(addrToUsers[userAddr].code) != 0;
    }

    function getUserParentInfo(address owner) view public returns (address parent,uint256 level) {
        parent = addrToUsers[owner].parent;
        level = parentLevel[parent];
    }

    function getUserInfo(address owner) view public returns (bytes32 code, address parent,uint level) {
        code = addrToUsers[owner].code;
        parent = addrToUsers[owner].parent;
        level = parentLevel[owner];
    }


    function getUserInfoByCode(bytes32 code) view external returns (address owner, uint level) {
        owner = codeOwners[code];
        level = parentLevel[owner];
    }

     function getTradeFeeRewardRate(address user) view external returns(uint myTransactionReward,uint myReferralReward){
         address  parent = addrToUsers[user].parent;
         uint level = 0;
         if(parent == address(0)){
             myTransactionReward  = 0;
         }else{
             level = parentLevel[parent] >0 ? parentLevel[parent]: 1;
             myTransactionReward = levelTradeFeeRewardRate[level];
         }
         level = parentLevel[user] >0 ? parentLevel[user]: 1;
         myReferralReward  = levelTradeFeeRewardRate[level];
     }

    function getUserParentWithLevel(address owner, uint maxLevel) view external returns (address[] memory parentsAddress){
        address[] memory tempParentUser = new address[](maxLevel);
        address currParent = owner;
        uint cnt = 0;
        for (uint i = 0; i < maxLevel; i++) {
            currParent = addrToUsers[currParent].parent;
            if (currParent == address(0)) {
                break;
            } else {
                tempParentUser[i] = currParent;
                cnt++;
            }
        }
        // Downsize the array to fit.
        assembly {
            mstore(parentsAddress, cnt)
        }
    }

    function getUserChildLen(address owner) view external returns (uint len) {
        len = addrToUsers[owner].child.length;
    }

    function getUserChild(address owner, uint startIndex, uint endIndex) view external returns (address[] memory childAddr) {
        uint len = addrToUsers[owner].child.length;
        if (len == 0) {
            return childAddr;
        }
        if (endIndex == 0) {
            startIndex = 0;
            endIndex = len;
        } else if (endIndex > len) {
            endIndex = len;
        }

        require(startIndex < endIndex, "invalid index");
        childAddr = new address[](endIndex - startIndex);
        for (uint256 i = startIndex; i != endIndex; ++i) {
            childAddr[i - startIndex] = addrToUsers[owner].child[i];
        }
    }

    function getFeeRewardRate() external view returns (uint[] memory, uint[] memory) {
        return (levelTradeFeeRewardRate, levelInviteFeeRewardRate);
    }

    function genCodeBytes32() public returns (bytes32 code){
        uint currentBlock = lastBlockCnt >> 8;
        uint8 txCnt = uint8(lastBlockCnt);
        if (currentBlock != block.number) {
            currentBlock = block.number;
            txCnt = 0;
        } else {
            txCnt++;
        }
        require(txCnt <= 99, 'cnt MAX');
        uint no = (block.timestamp) * 100 + txCnt;
        code = uintToBytes32(no, 36);
        lastBlockCnt = (block.number << 8) | txCnt;
    }

    function uintToBytes32(uint256 a, uint256 radix) internal pure returns (bytes32) {
        if (a == 0) {
            return bytes32(a);
        }
        uint bs;
        for (uint256 i = 0; a != 0; ++i) {
            uint256 b = a % radix;
            a /= radix;
            if (b < 10) {
                bs = uint(uint8(b + 48)) << (8 * i) | bs;
            } else {
                bs = uint(uint8(b + 55)) << (8 * i) | bs;
            }
        }
        return bytes32(bs);
    }

    function bytes32ToString(bytes32 x) public pure returns (string memory){
        bytes memory bytesString = new bytes(32);
        uint charCount = 0;
        for (uint j = 31; j >= 0;) {
            bytes1 char = bytes1(uint8(uint(x) >> (8 * j)));
            if (char != 0) {
                bytesString[charCount] = char;
                charCount++;
            }
            if (j == 0) {
                break;
            }
            j--;
        }
        bytes memory bytesStringTrimmed = new bytes(charCount);
        for (uint j = 0; j < charCount; j++) {
            bytesStringTrimmed[j] = bytesString[j];
        }
        return string(bytesStringTrimmed);
    }


    function stringToBytes32(string memory strCode) external pure returns (bytes32 result){
        bytes memory codeArr = bytes(strCode);
        uint codeInt;
        for (uint i = 0; i < codeArr.length; i++) {
            codeInt = codeInt << 8 | uint8(codeArr[i]);
        }
        result = bytes32(codeInt);
    }


    function getPendingLPReward(address _user,uint256 _type) external view returns(uint256){
        return userLPClaimTotal[_user][_type] - userLPClaimed[_user][_type];
    }

    function getPendingESLionReward(address _user,uint256 _type) external view returns(uint256){
        return userESLionClaimTotal[_user][_type] - userESLionClaimed[_user][_type];
    }
}

