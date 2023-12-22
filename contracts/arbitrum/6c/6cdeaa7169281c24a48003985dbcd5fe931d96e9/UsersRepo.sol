// SPDX-License-Identifier: UNLICENSED

/* *
 * Copyright (c) 2021-2023 LI LI @ JINGTIAN & GONGCHENG.
 *
 * This WORK is licensed under ComBoox SoftWare License 1.0, a copy of which 
 * can be obtained at:
 *         [https://github.com/paul-lee-attorney/comboox]
 *
 * THIS WORK IS PROVIDED ON AN "AS IS" BASIS, WITHOUT 
 * WARRANTIES OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED 
 * TO NON-INFRINGEMENT, MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE. IN NO 
 * EVENT SHALL ANY CONTRIBUTOR BE LIABLE TO YOU FOR ANY DAMAGES.
 *
 * YOU ARE PROHIBITED FROM DEPLOYING THE SMART CONTRACTS OF THIS WORK, IN WHOLE 
 * OR IN PART, FOR WHATEVER PURPOSE, ON ANY BLOCKCHAIN NETWORK THAT HAS ONE OR 
 * MORE NODES THAT ARE OUT OF YOUR CONTROL.
 * */

pragma solidity ^0.8.8;

import "./LockersRepo.sol";

library UsersRepo {
    using LockersRepo for LockersRepo.Repo;

    struct Key {
        address pubKey;
        uint16 discount;
        uint40 gift; 
        uint40 coupon;
    }

    struct User {
        Key primeKey;
        Key backupKey;
    }

    struct Rule {
        uint40 eoaRewards;
        uint40 coaRewards;
        uint40 floor;
        uint16 rate;
        uint16 para;
    }

    struct Repo {
        // userNo => User
        mapping(uint256 => User) users;
        // key => userNo
        mapping(address => uint) userNo;
        LockersRepo.Repo lockers;       
    }

    // platformRule: Rule({
    //     eoaRewards: users[0].primeKey.gift,
    //     coaRewards: users[0].backupKey.gift,
    //     floor: users[0].backupKey.coupon,
    //     rate: users[0].primeKey.discount,
    //     para: users[0].backupKey.discount
    // });

    // counterOfUers: users[0].primeKey.coupon;

    // ####################
    // ##    Modifier    ##
    // ####################

    modifier onlyOwner(Repo storage repo, address msgSender) {
        require(msgSender == getOwner(repo), 
            "UR.mf.OO: not owner");
        _;
    }

    modifier onlyKeeper(Repo storage repo, address msgSender) {
        require(msgSender == getBookeeper(repo), 
            "UR.mf.OK: not bookeeper");
        _;
    }

    modifier onlyPrimeKey(Repo storage repo, address msgSender) {
        require(msgSender == repo.users[getUserNo(repo, msgSender)].primeKey.pubKey, 
            "UR.mf.OPK: not primeKey");
        _;
    }

    // ########################
    // ##    Opts Setting    ##
    // ########################

    function ruleParser(bytes32 sn) public pure 
        returns(Rule memory rule) 
    {
        uint _sn = uint(sn);

        rule = Rule({
            eoaRewards: uint40(_sn >> 216),
            coaRewards: uint40(_sn >> 176),
            floor: uint40(_sn >> 136),
            rate: uint16(_sn >> 120),
            para: uint16(_sn >> 96)
        });
    }

    function setPlatformRule(Repo storage repo, bytes32 snOfRule, address msgSender) 
        public onlyOwner(repo, msgSender) onlyPrimeKey(repo, msgSender) 
    {

        Rule memory rule = ruleParser(snOfRule);

        User storage opt = repo.users[0];

        opt.primeKey.discount = rule.rate;
        opt.primeKey.gift = rule.eoaRewards;

        opt.backupKey.discount = rule.para;
        opt.backupKey.gift = rule.coaRewards;
        opt.backupKey.coupon = rule.floor;
    }

    function getPlatformRule(Repo storage repo) public view 
        returns (Rule memory rule) 
    {
        User storage opt = repo.users[0];

        rule = Rule({
            eoaRewards: opt.primeKey.gift,
            coaRewards: opt.backupKey.gift,
            floor: opt.backupKey.coupon,
            rate: opt.primeKey.discount,
            para: opt.backupKey.discount
        });
    }

    function transferOwnership(Repo storage repo, address newOwner, address msgSender) 
        public onlyOwner(repo, msgSender)
    {
        repo.users[1].primeKey.pubKey = newOwner;
    }

    function handoverCenterKey(Repo storage repo, address newKeeper, address msgSender) 
        public onlyKeeper(repo, msgSender) 
    {
        repo.users[1].backupKey.pubKey = newKeeper;
    }

    // ==== Author Setting ====

    function infoParser(bytes32 info) public pure returns(Key memory)
    {
        uint _info = uint(info);

        Key memory out = Key({
            pubKey: address(0),
            discount: uint16(_info >> 80),
            gift: uint40(_info >> 40),
            coupon: uint40(_info)
        });

        return out;
    }

    function setRoyaltyRule(
        Repo storage repo,
        bytes32 snOfRoyalty,
        address msgSender
    ) public onlyPrimeKey(repo, msgSender) {

        Key memory rule = infoParser(snOfRoyalty);

        uint author = getUserNo(repo, msgSender);
        User storage a = repo.users[author];

        a.backupKey.discount = rule.discount;
        a.backupKey.gift = rule.gift;
        a.backupKey.coupon = rule.coupon;

    }

    function getRoyaltyRule(Repo storage repo, uint author)
        public view returns (Key memory) 
    {
        require (author > 0, 'zero author');

        Key memory rule = repo.users[author].backupKey;
        delete rule.pubKey;

        return rule;
    }

    // ##################
    // ##    Points    ##
    // ##################

    function mintAndLockPoints(Repo storage repo, uint to, uint amt, uint expireDate, bytes32 hashLock, address msgSender) 
        public onlyOwner(repo, msgSender) returns (LockersRepo.Head memory head)
    {
        head = _prepareLockerHead(repo, to, amt, expireDate, msgSender);
        repo.lockers.lockPoints(head, hashLock);
    }

    function _prepareLockerHead(
        Repo storage repo, 
        uint to, 
        uint amt, 
        uint expireDate, 
        address msgSender
    ) private view returns (LockersRepo.Head memory head) {
        uint40 caller = getUserNo(repo, msgSender);

        require((amt >> 128) == 0, 
            "UR.prepareLockerHead: amt overflow");

        head = LockersRepo.Head({
            from: caller,
            to: uint40(to),
            expireDate: uint48(expireDate),
            value: uint128(amt)
        });
    }

    function lockPoints(Repo storage repo, uint to, uint amt, uint expireDate, bytes32 hashLock, address msgSender) 
        public onlyPrimeKey(repo, msgSender) returns (LockersRepo.Head memory head)
    {
        head = _prepareLockerHead(repo, to, amt, expireDate, msgSender);
        repo.lockers.lockPoints(head, hashLock);
    }

    function lockConsideration(
        Repo storage repo, 
        uint to, 
        uint amt, 
        uint expireDate, 
        address counterLocker, 
        bytes calldata payload, 
        bytes32 hashLock, 
        address msgSender
    ) public onlyPrimeKey(repo, msgSender) returns (LockersRepo.Head memory head) {
        head = _prepareLockerHead(repo, to, amt, expireDate, msgSender);
        LockersRepo.Body memory body = LockersRepo.Body({
            counterLocker: counterLocker,
            payload: payload 
        });
        repo.lockers.lockConsideration(head, body, hashLock);
    }

    function pickupPoints(
        Repo storage repo, 
        bytes32 hashLock, 
        string memory hashKey,
        address msgSender
    ) public returns (LockersRepo.Head memory head) 
    {
        uint caller = getUserNo(repo, msgSender);
        head = repo.lockers.pickupPoints(hashLock, hashKey, caller);
    }

    function withdrawDeposit(
        Repo storage repo, 
        bytes32 hashLock, 
        address msgSender
    ) public onlyPrimeKey(repo, msgSender) returns (LockersRepo.Head memory head) {
        uint caller = getUserNo(repo, msgSender);
        head = repo.lockers.withdrawDeposit(hashLock, caller);
    }

    function getLocker(
        Repo storage repo,
        bytes32 hashLock
    ) public view returns (LockersRepo.Locker memory locker) 
    {
        locker = repo.lockers.getLocker(hashLock);
    }

    function getLocksList(
        Repo storage repo
    ) public view returns (bytes32[] memory) 
    {
        return repo.lockers.getSnList();
    }

    // ##########################
    // ##    User & Members    ##
    // ##########################

    // ==== reg user ====

    function _increaseCounterOfUsers(Repo storage repo) private returns (uint40) {
        repo.users[0].primeKey.coupon++;
        return repo.users[0].primeKey.coupon;
    }

    function regUser(Repo storage repo, address msgSender) public 
        returns (User memory )
    {

        require(!isKey(repo, msgSender), "UserRepo.RegUser: used key");

        uint seqOfUser = _increaseCounterOfUsers(repo);

        repo.userNo[msgSender] = seqOfUser;

        User memory user;

        user.primeKey.pubKey = msgSender;

        Rule memory rule = getPlatformRule(repo);

        if (_isContract(msgSender)) {
            user.primeKey.discount = 1;
            user.primeKey.gift = rule.coaRewards;
        } else user.primeKey.gift = rule.eoaRewards;

        repo.users[seqOfUser] = user;

        return user;
    }

    function _isContract(address acct) private view returns (bool) {
        uint32 size;
        assembly {
            size := extcodesize(acct)
        }
        return size != 0;
    }

    function setBackupKey(Repo storage repo, address bKey, address msgSender) 
        public onlyPrimeKey(repo, msgSender)
    {
        require (!isKey(repo, bKey), "UR.SBK: used key");

        uint caller = getUserNo(repo, msgSender);

        User storage user = repo.users[caller];

        require(user.backupKey.pubKey == address(0), 
            "UR.SBK: already set backupKey");
        
        user.backupKey.pubKey = bKey;

        repo.userNo[bKey] = caller;
    }

    function upgradeBackupToPrime(
        Repo storage repo,
        address msgSender
    ) public {
        User storage user = repo.users[getUserNo(repo, msgSender)];
        (user.primeKey.pubKey, user.backupKey.pubKey) =
            (user.backupKey.pubKey, user.primeKey.pubKey);
    }


    // ##############
    // ## Read I/O ##
    // ##############

    // ==== options ====

    function counterOfUsers(Repo storage repo) public view returns (uint40) {
        return repo.users[0].primeKey.coupon;
    }

    function getOwner(Repo storage repo) public view returns (address) {
        return repo.users[1].primeKey.pubKey;
    }

    function getBookeeper(Repo storage repo) public view returns (address) {
        return repo.users[1].backupKey.pubKey;
    }

    // ==== register ====

    function isKey(Repo storage repo, address key) public view returns (bool) {
        return repo.userNo[key] > 0;
    }

    function getUser(Repo storage repo, address msgSender) 
        public view returns (User memory)
    {
        return repo.users[getUserNo(repo, msgSender)];
    }

    function getUserNo(Repo storage repo, address msgSender) 
        public view returns(uint40) 
    {
        uint40 user = uint40(repo.userNo[msgSender]);

        if (user > 0) return user;
        else revert ("UR.getUserNo: not registered");
    }
}

