// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Pausable.sol";
import "./SafeMath.sol";
import "./IERC20.sol";
import "./Ownable.sol";
import "./console.sol";

contract User is Pausable, Ownable {
    using SafeMath for uint256;

    mapping(address => address) public referrers;
    mapping(address => address) public parents;
    mapping(address => address[]) public listRef;
    mapping(address => uint256) public userRefCount;
    mapping(address => bool) public isRegister;

    address public receiver = 0x32a703bB4C40371050b156bEB892f238c247a965;
    uint256 public totalUser = 0;
    uint256 public feeActive = 3000000000000000000;

    event NewReferral(
        address indexed account,
        address ref,
        address parent
    );
    event UpdateRefUser(
        address indexed account,
        address newRefaccount,
        address parent
    );

    constructor() {
        isRegister[address(0)] = true;
    }

    function register(address _referrer, address _parent) public {
        require(isRegister[_referrer], "your sponsor is not registered");
        require(!isRegister[msg.sender], "you have already registered.");
        require(msg.sender != _referrer, "you cannot introduce myself.");

        referrers[msg.sender] = _referrer;
        parents[msg.sender] = _parent;
        isRegister[msg.sender] = true;
        listRef[_referrer].push(msg.sender);
        userRefCount[_referrer]++;
        totalUser++;

        emit NewReferral(msg.sender, _referrer, _parent);
    }

    function active() public {
        require(!isRegister[msg.sender], "you have already registered.");
        isRegister[msg.sender] = true;
        emit NewReferral(msg.sender, address(0), address(0));
    }

    function updateRefUser(
        address account,
        address newRefAccount,
        address parent
    ) public onlyOwner {
        // remove item listRef
        for (uint256 i = 0; i < listRef[referrers[account]].length; i++) {
            if (listRef[referrers[account]][i] == account) {
                listRef[referrers[account]][i] = listRef[referrers[account]][
                    listRef[referrers[account]].length - 1
                ];
                listRef[referrers[account]].pop();
                break;
            }
        }

        // update
        if (userRefCount[referrers[account]] > 0) {
            userRefCount[referrers[account]] = userRefCount[referrers[account]]
                .sub(1);
        }
        userRefCount[newRefAccount] = userRefCount[newRefAccount].add(1);
        referrers[account] = newRefAccount;
        parents[account] = parent;
        isRegister[account] = true;
        listRef[newRefAccount].push(account);
        emit UpdateRefUser(account, newRefAccount, parent);
        emit NewReferral(account, newRefAccount, parent);
    }

    function getRef(address account) public view returns (address) {
        return referrers[account];
    }

    function getIsRegister(address account) public view returns (bool) {
        return isRegister[account];
    }

    function setIsRegister(address _account, bool _result) public onlyOwner {
        isRegister[_account] = _result;
    }

    function getListRefLength(address _account) public view returns (uint256) {
        return listRef[_account].length;
    }

    function setReceiver(address _address) public onlyOwner {
        receiver = _address;
    }

    function setFeeActive(uint256 _fee) public onlyOwner {
        feeActive = _fee;
    }

    function clearUnknownToken(address _tokenAddress) public onlyOwner {
        uint256 contractBalance = IERC20(_tokenAddress).balanceOf(
            address(this)
        );
        IERC20(_tokenAddress).transfer(address(msg.sender), contractBalance);
    }
}

