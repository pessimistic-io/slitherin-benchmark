// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IHuntGameRandomRequester.sol";

import "./IERC1155.sol";
import "./IERC721.sol";
import "./ERC721Holder.sol";
import "./ERC1155Holder.sol";

import "./HuntGameDeployer.sol";
import "./IHunterValidator.sol";
import "./IHuntNFTFactory.sol";
import "./ReentrancyGuard.sol";
import "./GlobalNftLib.sol";

contract HuntGame is ERC721Holder, ERC1155Holder, ReentrancyGuard, IHuntGame, IHuntGameRandomRequester {
    /// cfg in factory
    IHuntNFTFactory public override factory;
    uint64 public override gameId;
    uint256 public override userNonce;

    /// cfg in game
    address public override owner;
    IHunterValidator public override validator;
    uint64 public override ddl;
    uint256 public override bulletPrice;
    uint64 public override totalBullets;
    address public override getPayment;
    /// cfg about nft
    IHuntGame.NFTStandard public override nftStandard;
    address public override nftContract;
    uint64 public override originChain;
    uint256 public override tokenId;

    IHuntGame.Status public override status;
    HunterInfo[] public override tempHunters;
    uint256 public override randomNum;
    uint256 public override requestId;
    address private _winner;
    bool public override nftPaid;
    bool public override ownerPaid;

    /////////////////////////////

    modifier depositing() {
        require(status == Status.Depositing, "only depositing");
        _;
    }

    modifier hunting() {
        /// @notice should not reach the ddl when hunting
        require(block.timestamp < ddl, "ddl");
        require(status == Status.Hunting, "only hunting");
        _;
    }

    modifier waiting() {
        require(status == Status.Waiting, "only waiting");
        _;
    }

    modifier timeout() {
        require(status == Status.Timeout, "only timeout");
        _;
    }

    modifier unclaimed() {
        require(status == Status.Unclaimed, "only unclaimed");
        _;
    }

    function initialize(
        IHunterValidator _hunterValidator,
        IHuntGame.NFTStandard _nftStandard,
        uint64 _totalBullets,
        uint256 _bulletPrice,
        address _nftContract,
        uint64 _originChain,
        address _getPayment,
        IHuntNFTFactory _factory,
        uint256 _tokenId,
        uint64 _gameId,
        uint64 _ddl,
        address _owner
    ) public {
        require(gameId == 0 && _gameId > 0); // notice avoid initialize twice and reentrancy
        gameId = _gameId;

        userNonce = IHuntGameDeployer(msg.sender).userNonce(_owner);
        validator = _hunterValidator;
        nftStandard = _nftStandard;
        totalBullets = _totalBullets;
        bulletPrice = _bulletPrice;
        nftContract = _nftContract;
        originChain = _originChain;
        getPayment = _getPayment;
        factory = _factory;
        tokenId = _tokenId;
        ddl = _ddl;
        owner = _owner;
        if (address(validator) != address(0)) {
            validator.huntGameRegister();
        }
    }

    function startHunt() public nonReentrant depositing {
        require(
            GlobalNftLib.isOwned(
                factory.getHuntBridge(),
                originChain,
                nftStandard == NFTStandard.GlobalERC1155,
                nftContract,
                tokenId
            ),
            "depositing"
        );
        /// @dev now start hunt
        status = Status.Hunting;
        emit Hunting();
    }

    function hunt(uint64 bullet) public payable {
        hunt(msg.sender, bullet, false, "");
    }

    function hunt(address hunter, uint64 bullet, bool _isFromAssetManager, bytes memory payload) public payable {
        if (getPayment == address(0)) {
            huntInNative(hunter, bullet, bullet, _isFromAssetManager, payload);
        } else {
            hunt(hunter, bullet, bullet, _isFromAssetManager, payload);
        }
    }

    function huntInNative(
        address _hunter,
        uint64 _bulletNum,
        uint64 _minNum,
        bool _isFromAssetManager,
        bytes memory _payload
    ) public payable nonReentrant hunting returns (uint64) {
        require(getPayment == address(0), "eth wanted");
        require(_bulletNum * bulletPrice == msg.value, "wrong value");
        require(_bulletNum > 0, "empty bullet");

        uint64 _before = 0;
        if (tempHunters.length > 0) {
            _before = tempHunters[tempHunters.length - 1].totalBullets;
        }
        require(_before < totalBullets, "over bullet");
        if (_before + _bulletNum > totalBullets) {
            _bulletNum = totalBullets - _before;
        }
        require(_bulletNum >= _minNum, "left not enough");
        /// @dev should never happen except reentrancy
        assert(_before + _bulletNum <= totalBullets);

        _beforeBuy(_hunter, _bulletNum, _payload);
        if (_before + _bulletNum == totalBullets) {
            _waitForRandom();
        }
        HunterInfo memory _info = HunterInfo({
            hunter: _hunter,
            bulletsAmountBefore: _before,
            bulletNum: _bulletNum,
            totalBullets: _before + _bulletNum,
            isFromAssetManager: _isFromAssetManager
        });
        tempHunters.push(_info);
        emit Hunted(uint64(tempHunters.length) - 1, _info);

        /// overflow same
        uint256 _refund = (msg.value - _bulletNum * bulletPrice);
        /// @dev if there left some eth, refund to sender
        if (_refund > 0) {
            payable(msg.sender).transfer(_refund);
        }
        _afterBuy();
        return _bulletNum;
    }

    function hunt(
        address _hunter,
        uint64 _bulletNum,
        uint64 _minNum,
        bool _isFromAssetManager,
        bytes memory _payload
    ) public nonReentrant hunting returns (uint64) {
        /// @notice receive erc20 token
        require(getPayment != address(0), "eth not allowed");
        require(_bulletNum > 0);
        uint64 _before = 0;
        if (tempHunters.length > 0) {
            _before = tempHunters[tempHunters.length - 1].totalBullets;
        }
        require(_before < totalBullets, "over bullet");
        if (_before + _bulletNum > totalBullets) {
            _bulletNum = totalBullets - _before;
        }
        require(_bulletNum >= _minNum, "left not enough");
        /// @dev should never happen
        assert(_before + _bulletNum <= totalBullets);

        _beforeBuy(_hunter, _bulletNum, _payload);
        /// overflow safe
        uint256 _amount = _bulletNum * bulletPrice;
        factory.huntGameClaimPayment(msg.sender, getPayment, _amount);
        if (_before + _bulletNum == totalBullets) {
            _waitForRandom();
        }
        HunterInfo memory _info = HunterInfo({
            hunter: _hunter,
            bulletsAmountBefore: _before,
            bulletNum: _bulletNum,
            totalBullets: _before + _bulletNum,
            isFromAssetManager: _isFromAssetManager
        });
        tempHunters.push(_info);
        emit Hunted(uint64(tempHunters.length) - 1, _info);

        _afterBuy();
        return _bulletNum;
    }

    function fillRandom(uint256 _randomNum) public waiting {
        require(msg.sender == address(factory));
        assert(randomNum == 0);
        randomNum = _randomNum;
        status = Status.Unclaimed;
        emit Unclaimed();
    }

    function claimTimeout() public {
        require(status == Status.Hunting || status == Status.Waiting);
        require(block.timestamp > ddl, "in time");
        status = Status.Timeout;
        emit Timeout();
    }

    function timeoutWithdrawBullets(uint64[] calldata _hunterIndexes) public timeout {
        require(_hunterIndexes.length > 0);
        for (uint256 i = 0; i < _hunterIndexes.length; i++) {
            uint64 _num = tempHunters[_hunterIndexes[i]].bulletNum;
            require(_num > 0, "no bullets");
            tempHunters[_hunterIndexes[i]].bulletNum = 0;
            uint256 _amount = uint256(_num) * bulletPrice;
            _pay(tempHunters[_hunterIndexes[i]].hunter, _amount, tempHunters[_hunterIndexes[i]].isFromAssetManager);
        }
        emit HunterWithdrawal(_hunterIndexes);
    }

    function timeoutWithdrawNFT() public payable {
        timeoutClaimNFT(true);
    }

    function timeoutClaimNFT(bool withdraw) public payable timeout {
        /// @notice do not try to pay twice
        require(!nftPaid, "paid");
        nftPaid = true;
        GlobalNftLib.transfer(
            factory.getHuntBridge(),
            originChain,
            nftStandard == NFTStandard.GlobalERC1155,
            nftContract,
            tokenId,
            owner,
            withdraw
        );
        emit NFTClaimed(owner);
    }

    function claimNft(uint64 _winnerIndex) public payable {
        claimNft(_winnerIndex, true);
    }

    function claimNft(uint64 _winnerIndex, bool _withdraw) public payable unclaimed {
        /// @notice do not try to pay twice
        require(!nftPaid, "paid");
        nftPaid = true;
        uint256 luckyBullet = (randomNum % totalBullets) + 1;
        require(_winnerIndex < tempHunters.length, "Index overflow");
        require(
            tempHunters[_winnerIndex].bulletsAmountBefore < luckyBullet &&
                tempHunters[_winnerIndex].totalBullets >= luckyBullet,
            "Not winner"
        );
        if (nftPaid && ownerPaid) {
            status = Status.Claimed;
            emit Claimed();
        }
        _winner = tempHunters[_winnerIndex].hunter;
        GlobalNftLib.transfer(
            factory.getHuntBridge(),
            originChain,
            nftStandard == NFTStandard.GlobalERC1155,
            nftContract,
            tokenId,
            _winner,
            _withdraw
        );
        emit NFTClaimed(_winner);
    }

    function claimReward() public unclaimed {
        require(!ownerPaid, "paid");
        ownerPaid = true;
        emit OwnerPaid();
        if (nftPaid && ownerPaid) {
            status = Status.Claimed;
            emit Claimed();
        }
        uint256 _amount = uint256(totalBullets) * bulletPrice;
        uint256 _fee = factory.getFeeManager().calcFee(_amount);
        _pay(owner, _amount - _fee, false);
        _pay(address(factory.getFeeManager()), _fee, false);
    }

    function getWinnerIndex() public view returns (uint64) {
        require(randomNum != 0, "not filled yet");
        uint256 luckyBullet = (randomNum % totalBullets) + 1;
        for (uint256 i = 0; i < tempHunters.length; i++) {
            if (tempHunters[i].bulletsAmountBefore < luckyBullet && tempHunters[i].totalBullets >= luckyBullet) {
                return uint64(i);
            }
        }
        revert("wired");
    }

    function winner() public view returns (address) {
        require(randomNum != 0, "not filled yet");
        if (_winner != address(0)) {
            return _winner;
        }
        uint256 luckyBullet = (randomNum % totalBullets) + 1;
        for (uint256 i = 0; i < tempHunters.length; i++) {
            if (tempHunters[i].bulletsAmountBefore < luckyBullet && tempHunters[i].totalBullets >= luckyBullet) {
                return tempHunters[i].hunter;
            }
        }
        revert("wired");
    }

    function estimateFees() public view returns (uint256) {
        if (originChain == block.chainid) {
            //no need to bridge back
            return 0;
        }
        return factory.getHuntBridge().estimateFees(originChain);
    }

    function canHunt(address hunter, uint64 bullet) public view returns (bool) {
        return canHunt(msg.sender, hunter, bullet, "");
    }

    function canHunt(address sender, address hunter, uint64 bullet, bytes memory payload) public view returns (bool) {
        if (address(validator) == address(0)) {
            /// @dev all pass
            return true;
        }
        return validator.isHunterPermitted(sender, msg.sender, hunter, bullet, payload);
    }

    function leftBullet() public view returns (uint64) {
        return tempHunters.length == 0 ? totalBullets : totalBullets - tempHunters[tempHunters.length - 1].totalBullets;
    }

    function _waitForRandom() internal {
        status = Status.Waiting;
        emit Waiting();
        requestId = factory.requestRandomWords();
    }

    function _beforeBuy(address _hunter, uint64 _bulletNum, bytes memory _payload) internal {
        if (address(validator) != address(0)) {
            validator.validateHunter(address(this), msg.sender, _hunter, _bulletNum, _payload);
        }
    }

    function _afterBuy() internal {}

    /// @notice reduce the bullets before call this method
    function _pay(address addr, uint256 _amount, bool isFromAssetManager) internal {
        if (getPayment == address(0)) {
            //eth, transfer
            if (isFromAssetManager) {
                factory.getHunterAssetManager().deposit{ value: _amount }(addr);
            } else {
                payable(addr).transfer(_amount);
            }
        } else {
            if (isFromAssetManager) {
                factory.getHunterAssetManager().deposit(addr, getPayment, _amount);
            } else {
                IERC20(getPayment).transfer(addr, _amount);
            }
        }
    }
}

