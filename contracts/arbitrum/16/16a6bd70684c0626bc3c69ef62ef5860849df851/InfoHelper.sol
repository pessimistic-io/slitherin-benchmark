// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SafeMath.sol";
import "./Address.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
// import "../core/interfaces/IVault.sol";
import "./IESBT.sol";

interface ShaHld {
    function getReferalState(address _account) external view returns (uint256, uint256[] memory, address[] memory , uint256[] memory, bool[] memory);
}

interface IDataStore{
    function getAddressSetCount(bytes32 _key) external view returns (uint256);
    function getAddressSetRoles(bytes32 _key, uint256 _start, uint256 _end) external view returns (address[] memory);
    function getAddUint(address _account, bytes32 key) external view returns (uint256);
    function getUint(bytes32 key) external view returns (uint256);
}


contract InfoHelper {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    bytes32 public constant ACCUM_REBATE = keccak256("ACCUM_REBATE");
    bytes32 public constant VALID_VAULTS = keccak256("VALID_VAULTS");
    bytes32 public constant ACCUM_SWAP = keccak256("ACCUM_SWAP");
    bytes32 public constant ACCUM_ADDLIQUIDITY = keccak256("ACCUM_ADDLIQUIDITY");
    bytes32 public constant ACCUM_POSITIONSIZE = keccak256("ACCUM_POSITIONSIZE");
    bytes32 public constant ACCUM_FEE_DISCOUNTED = keccak256("ACCUM_FEE_DISCOUNTED");
    bytes32 public constant ACCUM_FEE = keccak256("ACCUM_FEE");
    bytes32 public constant FEE_REBATE_PERCENT = keccak256("FEE_REBATE_PERCENT");
    bytes32 public constant ACCUM_SCORE = keccak256("ACCUM_SCORE");
    bytes32 public constant ACCUM_FEE_REBATED = keccak256("ACCUM_FEE_REBATED");

    bytes32 public constant INTERVAL_RANK_UPDATE = keccak256("INTERVAL_RANK_UPDATE");
    bytes32 public constant INTERVAL_SCORE_UPDATE = keccak256("INTERVAL_SCORE_UPDATE");
    bytes32 public constant TIME_RANK_UPD = keccak256("TIME_RANK_UPD");
    bytes32 public constant TIME_SOCRE_DEC= keccak256("TIME_SOCRE_DEC");


    uint256 constant private PRECISION_COMPLE = 10000;
    uint256 public constant SCORE_PRECISION = 10 ** 18;

    function getInvitedUser(address _ESBT, address _account) public view returns (address[] memory, uint256[] memory) {
        (, address[] memory childs) = IESBT(_ESBT).getReferralForAccount(_account);

        uint256[] memory infos = new uint256[](childs.length*3);

        for (uint256 i =0; i < childs.length; i++){
            infos[i*3] = IESBT(_ESBT).createTime(childs[i]);
            infos[i*3 + 1] = IESBT(_ESBT).userSizeSum(childs[i]);
            infos[i*3 + 2] = IESBT(_ESBT).getScore(childs[i]);
        }
        return (childs, infos);
    }

    function getBasicInfo(address _ESBT, address _account) public view returns (string[] memory, address[] memory, uint256[] memory) {
        (, address[] memory childs) = IESBT(_ESBT).getReferralForAccount(_account);

        uint256[] memory infos = new uint256[](17);
        string[] memory infosStr = new string[](2);
        // address[] memory validVaults = IDataStore(_ESBT).getAddressSetRoles(VALID_VAULTS, 0, IDataStore(_ESBT).getAddressSetCount(VALID_VAULTS));
        (infos[0], infos[1]) = IESBT(_ESBT).accountToDisReb(_account);
        infos[2] = IESBT(_ESBT).userSizeSum(_account);
        infos[3] = IDataStore(_ESBT).getAddUint(_account,  ACCUM_SWAP);
        infos[4] = IDataStore(_ESBT).getAddUint(_account,  ACCUM_ADDLIQUIDITY);
        infos[5] = IDataStore(_ESBT).getAddUint(_account,  ACCUM_POSITIONSIZE);
        infos[6] = IDataStore(_ESBT).getAddUint(_account,  ACCUM_FEE_DISCOUNTED);
        infos[7] = IDataStore(_ESBT).getAddUint(_account,  ACCUM_FEE); 
        infos[8] = IDataStore(_ESBT).getAddUint(_account,  ACCUM_FEE_REBATED); 
        infos[9] = IESBT(_ESBT).getScore(_account);
        infos[10] = IESBT(_ESBT).rank(_account);
        infos[11] = IESBT(_ESBT).createTime(_account);
        infos[12] = IESBT(_ESBT).addressToTokenID(_account);

        infos[13] = IDataStore(_ESBT).getUint(INTERVAL_RANK_UPDATE);
        infos[14] = IDataStore(_ESBT).getUint(INTERVAL_SCORE_UPDATE);

        infos[15] = IDataStore(_ESBT).getAddUint(_account, TIME_RANK_UPD).add(infos[13]);
        infos[15] = infos[15] > infos[13] ? infos[15] : 0; 
        infos[16] = IDataStore(_ESBT).getAddUint(_account, TIME_SOCRE_DEC).add(infos[14]);
        infos[16] = infos[16] > infos[14] ? infos[16] : 0; 

        infosStr[0] = IESBT(_ESBT).nickName(_account);
        infosStr[1] = IESBT(_ESBT).getRefCode(_account);
        return (infosStr, childs, infos);
    }


    function needUpdate(address _shareAct, address _account) public view returns (uint256) {
        (uint256 _refNum, uint256[] memory _compList, address[] memory _userList, , ) = ShaHld(_shareAct).getReferalState(_account);

        if (_refNum == _userList.length) return 0;

        uint256 needUpd = 1;
        for (uint256 i = 0; i < _compList.length; i++){
            if (_compList[i] < PRECISION_COMPLE){
                needUpd = i + 1;
                break;
            }
        }
        return needUpd;
    }   
}

