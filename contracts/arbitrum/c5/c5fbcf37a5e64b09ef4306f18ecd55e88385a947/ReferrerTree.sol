// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9 <0.9.0;

import "./Ownable.sol";
import "./interfaces_IERC20.sol";
import "./ECDSA.sol";
import "./draft-EIP712.sol";

contract ReferrerTree is EIP712, Ownable {
  string private SIGNING_DOMAIN;
  string private SIGNATURE_VERSION;

  struct ReferrerInfo {
    uint256 id;
    address account;
    string email;
    string name;
    uint256 parent_id;
    uint256 percent_initial;
    uint256 percent_children;
    uint256 timestamp;
  }

  struct ApproveInfo {
    uint256 id;
    uint256 percent;
    uint256 timestamp;
  }

  struct RewardPercent {
    address account;
    uint256 percent;
  }

  uint256 public decimals = 10000;
  uint256 public total_referrer = 1;

  ApproveInfo[] private approveList;
  mapping (uint256 => mapping (uint256 => uint256)) private approveObj;

  mapping (uint256 => ReferrerInfo) public referrers;
  mapping (address => uint256[]) public referInfos;
  mapping (address => bool) public managers;

  event Approve(bytes callback);
  event Claim(address token, address account, uint256 amount);

  modifier onlyManager() {
    require(managers[msg.sender], "LC Refer: !manager");
    _;
  }

  constructor(string memory domain, string memory version)
    EIP712(domain, version) {
    SIGNING_DOMAIN = domain;
    SIGNATURE_VERSION = version;
    managers[msg.sender] = true;
  }

  receive() external payable {
  }

  function addTier(address account, string memory email, string memory name, bytes memory code, bytes memory signature) public {
    ApproveInfo memory info = abi.decode(code, (ApproveInfo));
    address signer = _verify(info, signature);
    require(managers[signer], "LC Refer: wrong signature");
    require(managers[msg.sender] || approveObj[info.id][info.timestamp] > 0, "LC Refer: not approved");

    _removeApprove(info);
    referrers[total_referrer] = ReferrerInfo({
      id: total_referrer,
      account: account,
      email: email,
      name: name,
      parent_id: info.id,
      percent_initial: info.percent,
      percent_children: 0,
      timestamp: uint256(block.timestamp)
    });
    referInfos[account].push(total_referrer);
    referrers[info.id].percent_children = referrers[info.id].percent_children + info.percent;
    total_referrer ++;
  }

  function editTier(uint256 id, uint256 percent) public {
    require(managers[msg.sender] || referrers[referrers[id].parent_id].account == msg.sender, "LC Refer: wrong access");
    referrers[referrers[id].parent_id].percent_children = referrers[referrers[id].parent_id].percent_children + percent - referrers[id].percent_initial;
    referrers[id].percent_initial = percent;
  }

  function deleteTier(uint256 id) public {
    require(managers[msg.sender] || referrers[referrers[id].parent_id].account == msg.sender, "LC Refer: wrong access");
    referrers[referrers[id].parent_id].percent_children = referrers[referrers[id].parent_id].percent_children - referrers[id].percent_initial;
    address acc = referrers[id].account;
    delete(referrers[id]);
    uint256 len = referInfos[acc].length;
    for (uint256 x = 0; x < len; x ++) {
      if (referInfos[acc][x] == id) {
        referInfos[acc][x] = referInfos[acc][len - 1];
        referInfos[acc].pop();
        break;
      }
    }
  }

  function approve(uint256 id, uint256 percent) public returns(bytes memory callback) {
    require(managers[msg.sender] || referrers[id].account == msg.sender, "LC Refer: wrong id");
    require(percent <= decimals, "LC Refer: wrong percent");

    uint256 ts = uint256(block.timestamp);
    ApproveInfo memory info = ApproveInfo({
      id: id,
      percent: percent,
      timestamp: ts
    });
    approveObj[id][ts] = percent;
    approveList.push(info);
    callback = abi.encode(info);
    emit Approve(callback);
  }

  function removeAllowance(bytes memory callback) public {
    ApproveInfo memory info = abi.decode(callback, (ApproveInfo));
    require(referrers[info.id].account == msg.sender || managers[msg.sender], "LC Refer: wrong access");
    _removeApprove(info);
  }

  function getUserInfos(address account) public view returns(uint256[] memory) {
    return referInfos[account];
  }

  function getUserRewards(address account) public view returns(uint256 reward) {
    uint256[] memory ids = getUserInfos(account);
    uint256 len = ids.length;
    reward = 0;
    for (uint256 x = 0; x < len; x ++) {
      reward += getRewardFromRoot(ids[x]);
    }
  }

  function getRewardFromRoot(uint256 id) public view returns(uint256 percent) {
    uint256 pos = id;
    percent = referrers[pos].percent_initial * (decimals - referrers[pos].percent_children) / decimals;
    while (referrers[pos].parent_id != 0) {
      pos = referrers[pos].parent_id;
      percent = percent * referrers[pos].percent_initial / decimals;
    }
  }

  function getAllReferrers() public view returns(address[] memory) {
    return _getVaildReferrers();
  }

  function getRewardMap() public view returns(uint256[] memory) {
    return _getRewardMap();
  }

  function claimReward(address[] memory tokens) public {
    address[] memory users = _getVaildReferrers();
    uint256[] memory mp = _getRewardMap();
    uint256 totalDec = 0;
    uint256 len = mp.length;
    for (uint256 i = 0; i < len; i ++) {
      totalDec += mp[i];
    }

    uint256 tlen = tokens.length;
    for (uint256 x = 0; x < tlen; x ++) {
      uint256 balance = address(this).balance;
      if (tokens[x] != address(0)) {
        balance = IERC20(tokens[x]).balanceOf(address(this));
      }

      for (uint256 i = 0; i < len; i ++) {
        uint256 reward = balance * mp[i] / totalDec;
        if (tokens[x] == address(0)) {
          reward = address(this).balance < reward ? address(this).balance : reward;
          if (reward > 0) {
            (bool success, ) = users[i].call{value: reward}("");
            require(success, "LC Refer: distribute reward");
            emit Claim(address(0), users[i], reward);
          }
        }
        else {
          reward = IERC20(tokens[x]).balanceOf(address(this)) < reward ? IERC20(tokens[x]).balanceOf(address(this)) : reward;
          if (reward > 0) {
            IERC20(tokens[x]).transfer(users[i], reward);
            emit Claim(tokens[x], users[i], reward);
          }
        }
      }
    }
  }

  function setManager(address _account, bool _access) public onlyOwner {
    managers[_account] = _access;
  }

  function _removeApprove(ApproveInfo memory info) private {
    uint256 len = approveList.length;
    for (uint256 x = 0; x < len; x ++) {
      if (approveList[x].id == info.id &&
        approveList[x].percent == info.percent &&
        approveList[x].timestamp == info.timestamp
      ) {
        approveList[x] = approveList[len - 1];
        approveList.pop();
        break;
      }
    }
    approveObj[info.id][info.timestamp] = 0;
  }

  function _getRewardMap() private view returns(uint256[] memory) {
    address[] memory users = _getVaildReferrers();
    uint256 len = users.length;
    uint256[] memory rewards = new uint256[](len);
    for (uint256 x = 0;  x < len; x ++) {
      rewards[x] = getUserRewards(users[x]);
    }
    return rewards;
  }

  function _getVaildReferrers() private view returns(address[] memory) {
    address[] memory users = new address[](total_referrer);
    uint256 i = 0;
    for (uint256 x = 0; x < total_referrer; x ++) {
      if (referrers[x].percent_initial > 0 && 
        referrers[x].account != address(0) &&
        _indexOf(users, referrers[x].account) == -1)
      {
        users[i] = referrers[x].account;
        i ++;
      }
    }

    address[] memory ret = new address[](i);
    for (uint256 x = 0; x < i; x ++) {
      ret[x] = users[x];
    }
    return ret;
  }

  function _indexOf(address[] memory arr, address key) internal pure returns(int256) {
    uint256 len = arr.length;
    for (uint256 x = 0; x < len; x ++) {
      if (arr[x] == key) return int256(x);
    }
    return -1;
  }

  function _hash(ApproveInfo memory info) internal view returns (bytes32) {
    return _hashTypedDataV4(keccak256(abi.encode(
      keccak256("ApproveInfo(uint256 id,uint256 percent,uint256 timestamp)"),
      info.id,
      info.percent,
      info.timestamp
    )));
  }

  function _verify(ApproveInfo memory info, bytes memory signature) internal view returns (address) {
    bytes32 digest = _hash(info);
    return ECDSA.recover(digest, signature);
  }

  function withdraw() public onlyOwner {
    (bool success, ) = payable(msg.sender).call{value: address(this).balance}("");
    require(success, "Failed to withdraw");
  }

  function withdrawT(address token) public onlyOwner {
    IERC20(token).transfer(msg.sender, IERC20(token).balanceOf(address(this)));
  }
}

