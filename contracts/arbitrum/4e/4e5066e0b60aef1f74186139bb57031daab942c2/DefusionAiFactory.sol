pragma solidity ^0.8.0;
// SPDX-License-Identifier: MIT

import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./SafeERC20.sol";
import "./ECDSA.sol";
import "./EIP712.sol";
import "./IDefusionAi.sol";
import "./IPlayerBook.sol";

interface IAIGC {
    function mint(address to, uint256 amount) external;

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
}

contract DefusionAiFactory is ReentrancyGuard, EIP712, Ownable {
    using SafeERC20 for IERC20;

    bool private initialized;

    address public defusionAi;
    address public aigc;
    address public signer;
    bool public airdrop;
    address public playbook;
    uint256 public referralRate; // 10% 100

    uint256 public intervalTime; // 30 days
    uint256 public punish; // 5%
    address public dev;

    event SetAirdrop(bool airdrop);
    event eveSetPunishParam(
        uint256 _intervalTime,
        uint256 _punish,
        address _dev
    );
    event SetReferralRate(uint256 referralRate);
    event UpdateSignerManager(address signer);
    event eveMint(
        uint256 indexed _tokenId,
        uint256 indexed _airdropAmount,
        address _mintTo,
        uint256 aigcType,
        address proj,
        uint256 stakeNum,
        uint256 dummyNum,
        uint256 timestamp
    );
    event eveDestroy(uint256 indexed _tokenId, address _mintTo);
    event eveBuyCredits(address sender, uint256 amount);

    constructor() EIP712("DefusionAi", "1.0.0") {}

    function initialize(
        address _owner,
        address signer_,
        address _dev
    ) external {
        require(!initialized, "initialize: Already initialized!");

        _transferOwnership(_owner);
        eip712Initialize("DefusionAi", "1.0.0");
        defusionAi = address(0xb2dd434C37E0370a4359F55D5Ed5BdB0ce2E3204);
        aigc = address(0x66738341f0Fd48befF97befd8A6C8ce98953a3dE);
        signer = signer_;
        airdrop = true;
        intervalTime = 30 days;
        punish = 5;
        dev = _dev;
        playbook = address(0x5CA715D5fB3a3F0499f72EC52d66A6c5a506ea4f);
        referralRate = 100;
        initialized = true;
    }

    function claimHash(
        uint256 _tokenId,
        uint256 _airdropAmount,
        address _mintTo,
        uint256 dummyNum,
        uint256 aigcType
    ) internal view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        keccak256(
                            "Mint(uint256 _tokenId,uint256 _airdropAmount,address mintTo,uint256 dummyNum,uint256 aigcType)"
                        ),
                        _tokenId,
                        _airdropAmount,
                        _mintTo,
                        dummyNum,
                        aigcType
                    )
                )
            );
    }

    function verifySignature(
        bytes32 hash,
        bytes calldata signature
    ) internal view returns (bool) {
        return ECDSA.recover(hash, signature) == signer;
    }

    function setManager(address _signer) external onlyOwner {
        signer = _signer;
        emit UpdateSignerManager(_signer);
    }

    function mint(
        uint256 _tokenId,
        uint256 _airdropAmount,
        address _mintTo,
        uint256 dummyNum,
        uint256 aigcType,
        bytes calldata _signature,
        address proj,
        uint256 num,
        string calldata affCode
    ) external nonReentrant {
        require(_mintTo == msg.sender, "_mintTo is not equal sender");
        require(
            verifySignature(
                claimHash(
                    _tokenId,
                    _airdropAmount,
                    _mintTo,
                    dummyNum,
                    aigcType
                ),
                _signature
            ),
            "Invalid signature"
        );
        uint256 stakeNum = 0;
        if (proj != address(0)) {
            uint256 balanceBefore = IERC20(proj).balanceOf(address(this));
            IERC20(proj).safeTransferFrom(_mintTo, address(this), num);
            uint256 balanceEnd = IERC20(proj).balanceOf(address(this));
            stakeNum = balanceEnd - balanceBefore;
        }

        IDefusionAi(defusionAi).mint(
            _mintTo,
            _tokenId,
            IDefusionAi.TokenInfo(
                aigcType,
                proj,
                stakeNum,
                dummyNum,
                block.timestamp
            )
        );

        if (!IPlayerBook(playbook).hasRefer(_mintTo)) {
            IPlayerBook(playbook).bindRefer(_mintTo, affCode);
        }

        if (airdrop) {
            IAIGC(aigc).mint(_mintTo, _airdropAmount);
            if (_airdropAmount > 0) {
                uint256 tenPercentV = _airdropAmount;
                uint256 referralV = (tenPercentV * referralRate) / 100;
                uint256 referralFee = IPlayerBook(playbook).settleReward(
                    _mintTo,
                    referralV
                );
                IAIGC(aigc).mint(playbook, referralFee);
            }
        }
        emit eveMint(
            _tokenId,
            _airdropAmount,
            _mintTo,
            aigcType,
            proj,
            stakeNum,
            dummyNum,
            block.timestamp
        );
    }

    function destroy(uint256 tokenId) external nonReentrant {
        IDefusionAi.TokenInfo memory tokenInfo = IDefusionAi(defusionAi)
            .getTokenInfo(tokenId);
        if ((block.timestamp - tokenInfo.timestamp) >= intervalTime) {
            if (tokenInfo.proj != address(0)) {
                IERC20(tokenInfo.proj).safeTransferFrom(
                    address(this),
                    msg.sender,
                    tokenInfo.num
                );
            }
        } else {
            // "It's not time to unlock yet!"
            if (tokenInfo.proj != address(0)) {
                uint256 punishAmount = (tokenInfo.num * punish) / 100;
                uint256 refundAmount = tokenInfo.num - punishAmount;
                IERC20(tokenInfo.proj).safeTransferFrom(
                    address(this),
                    msg.sender,
                    refundAmount
                );
                IERC20(tokenInfo.proj).safeTransferFrom(
                    address(this),
                    dev,
                    punishAmount
                );
            }
        }

        IDefusionAi(defusionAi).burn(tokenId);
        emit eveDestroy(tokenId, msg.sender);
    }

    function setAirdrop(bool airdrop_) external onlyOwner {
        require(airdrop != airdrop_, "Set different values!");
        airdrop = airdrop_;
        emit SetAirdrop(airdrop_);
    }

    function setPunishParam(
        uint256 _intervalTime,
        uint256 _punish,
        address _dev
    ) external onlyOwner {
        intervalTime = _intervalTime;
        punish = _punish;
        dev = _dev;
        emit eveSetPunishParam(_intervalTime, _punish, _dev);
    }

    function setReferralRate(uint256 _referralRate) external onlyOwner {
        referralRate = _referralRate;
        emit SetReferralRate(_referralRate);
    }

    function buyCredits(
        uint256 amount,
        string calldata affCode
    ) external nonReentrant {
        if (!IPlayerBook(playbook).hasRefer(msg.sender)) {
            IPlayerBook(playbook).bindRefer(msg.sender, affCode);
        }
        IAIGC(aigc).transferFrom(
            msg.sender,
            0x000000000000000000000000000000000000dEaD,
            amount
        );
        emit eveBuyCredits(msg.sender, amount);
    }
}

