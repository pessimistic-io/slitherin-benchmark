// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";

interface IVault{
    function getPosition(address _account, address _indexToken, bool _isLong, uint256 _insuranceLevel) external  view  returns (uint256, uint256, uint256, uint256, bool, uint256, uint256);
}

contract HoldMining is OwnableUpgradeable, PausableUpgradeable, UUPSUpgradeable  {
    using SafeERC20 for IERC20;
    // Info of each user.
    struct UserInfo {
        uint256 totalAmount; //deposit token's total amountß
        uint256 depositTime; //last deposit time
        uint256 withdrawTime; //last withdraw time
    }

    uint256 public BasePoint;
    uint256 public rewardRatio;
    address public signerAddress;
    uint256 public totalStaked; //sum user's deposit token amount
    //user=>user info
    mapping(address => UserInfo) public userInfo;
    mapping(address => uint256) public claimed;
    mapping(address=>mapping(bytes=>bool)) public claimTag;

    uint32 public startTime;
    uint32 public endTime;

    IERC20 public Lion;
    IERC20 public esLion;
    IVault public vault;

    address[] public  indexTokens;
    uint256[] public insuranceLevels;
    mapping(address => uint256) public lastClaimedTime;

    event Deposit(address indexed user,uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event Claim(address indexed user,uint256[] timeStamps,uint256 claimAmount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(){
        _disableInitializers();
    }

    function _authorizeUpgrade(address newImplementation) internal onlyOwner override {}


    function initialize(IERC20 _Lion, IERC20 _esLion, IVault _vault,address _signerAddress,uint32 _startTime) initializer public {
        __Ownable_init();
        __Pausable_init();

        BasePoint = 10000;
        rewardRatio = 8;
        Lion = _Lion;
        esLion = _esLion;
        vault = _vault;
        signerAddress = _signerAddress;
        startTime = _startTime;
        indexTokens.push(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
        indexTokens.push(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f);
        indexTokens.push(0x912CE59144191C1204E64559FE8253a0e49E6548);
        insuranceLevels.push(0);
        insuranceLevels.push(1);
        insuranceLevels.push(2);
        insuranceLevels.push(3);
        insuranceLevels.push(4);
        insuranceLevels.push(5);


    }
    // Deposit lion tokens
    function deposit(uint256 _amount) public whenNotPaused {
        require(
            startTime <= uint32(block.timestamp),
            "HoldMining: deposit not start yet"
        );
        require(_amount >0,"HoldMining: deposit amount wrong");
        UserInfo storage user = userInfo[msg.sender];

        Lion.safeTransferFrom(msg.sender, address(this), _amount);
        user.totalAmount += _amount;
        user.depositTime = block.timestamp;
        totalStaked += _amount;

        emit Deposit(msg.sender, _amount);
    }


    function withdraw(uint256 _amount) public {
        UserInfo storage user = userInfo[msg.sender];
        require(
            _amount > 0 && user.totalAmount >= _amount,
            "HoldMining: _amount invalid"
        );
        user.totalAmount -= _amount;
        totalStaked -= _amount;
        user.withdrawTime = block.timestamp;
        Lion.safeTransfer(address(msg.sender), _amount);
        emit Withdraw(msg.sender, _amount);
    }

    function claim(
        bytes memory signature,
        uint256[] memory timeStamps,
        uint256 amount
    ) external {
        require(signature.length == 65, "HoldMining: invalid signature");
        address sender = msg.sender;
        require(amount> 0, "HoldMining: amount zero");
        require(!claimTag[sender][signature],"HoldMining: these phase claimed");
        require(timeStamps[0] > lastClaimedTime[sender] ,"HoldMining: these phase claimed");
        (uint8 v, bytes32 r, bytes32 s) = splitSignature(signature);

        require(
            signerAddress ==
            ecrecover(
                keccak256(
                    abi.encodePacked(
                        "\x19Ethereum Signed Message:\n32",
                        keccak256(
                            abi.encodePacked(
                                sender,
                                block.chainid,
                                address(this),
                                timeStamps,
                                amount
                            )
                        )
                    )
                ),
                v,
                r,
                s
            ),
            "sign"
        );
        claimTag[sender][signature] = true;
        lastClaimedTime[sender] = timeStamps[timeStamps.length-1];
        esLion.safeTransfer(sender, amount);
        claimed[sender] += amount;
        emit Claim(sender,timeStamps,amount);
    }

    function splitSignature(
        bytes memory sig
    ) internal pure returns (uint8 v, bytes32 r, bytes32 s) {
        require(sig.length == 65);
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
        return (v, r, s);
    }

    // function getPosition(address _account,address _indexToken,bool _isLong,uint256 _insuranceLevel)
    function getPositions(address _user) public view returns(uint256 size) {
        for (uint256 i = 0; i < indexTokens.length; i++) {
            for(uint256 j=0; j<insuranceLevels.length;j++ ){
                (uint256 shortSize,,,,,,) = IVault(vault).getPosition(_user , indexTokens[i], false,insuranceLevels[j]);
                (uint256 longSize,,,,,,) = IVault(vault).getPosition(_user , indexTokens[i], true,insuranceLevels[j]);

                size += (shortSize + longSize);
            }
        }
    }

  function getReward(address _user) public view returns(uint256 size,uint256 reward,uint256 totalAmount){
      UserInfo storage user = userInfo[_user];
      size = getPositions(_user);
      totalAmount = user.totalAmount;
      if(totalAmount >0 && size >= totalAmount){
           reward = totalAmount*rewardRatio/BasePoint;
      }
  }

  function getUserInfo(
        address _user
    ) public view returns (uint256 totalAmount, uint256 userClaimed,uint256 depositTime, uint256 withdrawTime) {
        totalAmount = userInfo[_user].totalAmount;
        depositTime = userInfo[_user].depositTime;
        withdrawTime = userInfo[_user].withdrawTime;
        userClaimed = claimed[_user];
    }

   function getIndexTokensLen() public view returns(uint256 len){
       len = indexTokens.length;
   }
   function getInsuranceLevelsLen() public view returns(uint256 len){
        len = insuranceLevels.length;
   }
    function setSignerAddress(address _signerAddress) public onlyOwner {
        signerAddress = _signerAddress;
    }

    function setIndexTokens(address[] calldata _indexTokens) public onlyOwner {
        indexTokens = _indexTokens;
    }

    function setInsuranceLevels(uint256[] calldata _insuranceLevels) public onlyOwner {
        insuranceLevels = _insuranceLevels;
    }
    function setRewardRatio(uint32 _rewardRatio) public onlyOwner {
        rewardRatio = _rewardRatio;
    }
    function pause() external onlyOwner {
        _pause();
    }
    function unpause() external onlyOwner {
        _unpause();
    }
    function recoverWrongTokens(address _token, uint256 _amount) external onlyOwner {
        IERC20(_token).safeTransfer(msg.sender, _amount);
    }
}

