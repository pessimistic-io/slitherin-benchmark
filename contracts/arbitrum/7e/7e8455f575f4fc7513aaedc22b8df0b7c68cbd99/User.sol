// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Pausable.sol";
import "./SafeMath.sol";
import "./IERC20.sol";
import "./Ownable.sol";
import "./IMatrix.sol";

contract User is Pausable, Ownable {
    using SafeMath for uint256;

    mapping(address => address) public referrers;
    mapping(address => address[]) public listRef;
    mapping(address => uint256) public userRefCount;
    mapping(address => bool) public isRegister;

    address public matrix = address(0);
    uint256 public totalUser = 0;

    event NewReferral(address indexed account, address indexed ref);
    event UpdateRefUser(address indexed account, address indexed newRefaccount);

    constructor() {
        isRegister[0x3cd793d621BF33A5A53A8D178Fe139a7166f7eEf] = true;
        isRegister[0x1E7bf26943650036D8dB1F7E02cecB57A40a9EaC] = true;
        isRegister[0xf5C2DfBD58856AAEb6D5AbFB5D33fc752a42E080] = true;
        isRegister[0xC7D16B826307d617a8d0d5a4dA75CA6489Ee40eC] = true;
        isRegister[0x3bEd5Ac81fF78C6967118b1F57C3b409239734a7] = true;
        isRegister[0xc8B53094f613854089801ED1506E98a17b041347] = true;
        isRegister[0xc7a46678b6b745e28D2f36A8E53DfD2f85bD7014] = true;
        isRegister[0x0C5F850182381ba612D9799F8df3e5E6eFCaEB7A] = true;
        isRegister[0x55844fAFBf59Ef83FFe080f14D7c337406eb1279] = true;
        isRegister[0xC7779Bce731747CC494640202F0DC326D7b0D1d0] = true;
        isRegister[0x9508999820c274633f69B6E53470ae49E09D440A] = true;
        isRegister[0x80cCBa2C5c91400F910B4953B48fC6b2E6314c38] = true;
        isRegister[0xe31C54EC8e5Cd316aB0bfF7c5A13DE90D78Ae188] = true;
        isRegister[0xB02B2AA0a32B504AFc25B3cb789DDC0065b2139f] = true;
        isRegister[0xb893d2436e391D026C6Be28830Df4E3B6816B0C0] = true;
    }

    function register(address _referrer) public {
        require(isRegister[_referrer], "your sponsor is not registered");
        require(!isRegister[msg.sender], "you have already registered.");
        require(msg.sender != _referrer, "you cannot introduce myself.");

        referrers[msg.sender] = _referrer;
        isRegister[msg.sender] = true;
        listRef[_referrer].push(msg.sender);
        userRefCount[_referrer]++;
        totalUser++;

        IMatrix(matrix).setUserRoundDetail(msg.sender, 1, 0, block.timestamp);
        IMatrix(matrix).setAccountTimeVote(msg.sender, 1, 0, block.timestamp);

        emit NewReferral(msg.sender, _referrer);
    }

    function updateRefUser(
        address account,
        address newRefAccount
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
        isRegister[account] = true;
        listRef[newRefAccount].push(account);
        emit UpdateRefUser(account, newRefAccount);
        emit NewReferral(account, newRefAccount);

        IMatrix(matrix).setUserRoundDetail(account, 1, 0, block.timestamp);
        IMatrix(matrix).setAccountTimeVote(account, 1, 0, block.timestamp);
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

    function setMatrix(address _address) public onlyOwner {
        matrix = _address;
    }

    function clearUnknownToken(address _tokenAddress) public onlyOwner {
        uint256 contractBalance = IERC20(_tokenAddress).balanceOf(
            address(this)
        );
        IERC20(_tokenAddress).transfer(address(msg.sender), contractBalance);
    }
}

