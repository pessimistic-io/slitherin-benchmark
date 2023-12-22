pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./Ownable.sol";
import "./SafeERC20.sol";
import "./Lock.sol";

contract LockFactory is Ownable {
    using SafeERC20 for IERC20;
    IERC20 public token;
    LockInfo[] public lockInfos;

    struct LockInfo {
        address contractAddress;
        string name;
        address owner;
        uint256 amount;
    }

    mapping(string => LockInfo) public lockInfosByName;

    constructor() {}

    function updateLockToken(address _token) external onlyOwner {
        require(_token != address(0), "invalid token address");
        token = IERC20(_token);
    }

    function deploy(
        string memory _name,
        address _owner,
        uint256 _lockRange,
        uint256 _finishRange,
        uint256 _amount,
        uint8 _type
    ) public onlyOwner {
        require(bytes(_name).length != 0 && _owner != address(0));
        LockInfo storage info = lockInfosByName[_name];
        require(info.owner == address(0), "Lock::deploy: already deployed");

        info.contractAddress = address(
            new Lock(
                _name,
                address(this),
                _owner,
                _lockRange,
                _finishRange,
                _type
            )
        );
        info.name = _name;
        info.owner = _owner;
        info.amount = _amount;
        lockInfos.push(info);
    }

    function notifyRewardAmounts() public onlyOwner {
        require(lockInfos.length > 0, "Lock::notify: invalid length");
        for (uint i = 0; i < lockInfos.length; i++) {
            LockInfo storage info = lockInfos[i];
            if (info.amount > 0) {
                uint amount = info.amount;
                info.amount = 0;

                token.safeTransfer(info.contractAddress, amount);
                Lock(info.contractAddress).notify(amount);
            }
        }
    }
}

