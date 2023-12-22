// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.18;

import { IERC20Tax } from "./IERC20Tax.sol";
import { ERC20TaxReferenced } from "./ERC20TaxReferenced.sol";

import { ERC20 } from "./ERC20.sol";
import { IERC20 } from "./IERC20.sol";
import { ECDSA } from "./ECDSA.sol";


contract FireDogeAirdropPool is ERC20TaxReferenced {
    using ECDSA for bytes32;

    mapping(uint256 => bool) public usedNonce;
    mapping(address => bool) public claimedUser;
    uint256 public claimedUserCount;

    address private immutable AIRDROP_SIGNER;
    uint256 private immutable AIRDROP_START_TIME;

    uint256 private constant AIRDROP_DURATION = 7 days;
    uint256 private constant AIRDROP_AMOUNT_DENOMINATOR_AT_THE_END = 5;  // In 5 times less at the end
    uint256 private constant AIRDROP_REFERRER_PROPORTION = 5;  // 1/5
    uint256 private constant AIRDROP_MAX_USERS = 600_000;

    event AirdropClaim(
        uint128 nonce,
        uint256 distributedAmount,
        uint256 referrerAmount,
        address user,
        address referrer
    );

    constructor(
        address _signer
    ) {
        AIRDROP_SIGNER = _signer;
        AIRDROP_START_TIME = block.timestamp;
    }

    function claim(
        uint128 _nonce,
        bytes calldata _sign,
        address _referrer
    ) public virtual returns (bool) {
        bytes32 _message = keccak256(abi.encode(address(this), msg.sender, _nonce));
        bytes32 _ethSignedMessageHash = _message.toEthSignedMessageHash();

        address _signer = ECDSA.recover(_ethSignedMessageHash, _sign);

        require(_signer == AIRDROP_SIGNER, "Signer mismatched");
        require(block.timestamp <= AIRDROP_START_TIME + AIRDROP_DURATION, "Airdrop is ended");
        require(claimedUserCount <= AIRDROP_MAX_USERS, "Maximum claimed users are reached");
        require(!claimedUser[msg.sender], "You has been already claimed your rewards");
        require(!usedNonce[_nonce], "Nonce has been already used");
        require(msg.sender != _referrer, "Cannot assign yourself as referrer");

        uint256 _tokenTotalSupply = TOKEN.totalSupply();
        uint256 _maxRewardPerUser = _tokenTotalSupply / AIRDROP_MAX_USERS;

        uint256 _remainedTime = AIRDROP_START_TIME + AIRDROP_DURATION - block.timestamp;
        uint256 _remainedTimeInProportionX18 = _remainedTime * 1e18 / AIRDROP_DURATION;  // [0; 1e18]
        uint256 _rewardsDenominator = AIRDROP_AMOUNT_DENOMINATOR_AT_THE_END - (
            _remainedTimeInProportionX18 * AIRDROP_AMOUNT_DENOMINATOR_AT_THE_END / 1e18
        );
        uint256 _distributedAmount = _maxRewardPerUser / _rewardsDenominator;
        uint256 _referrerAmount = _distributedAmount / AIRDROP_REFERRER_PROPORTION;
        claimedUser[msg.sender] = true;
        usedNonce[_nonce] = true;

        require(
            TOKEN.balanceOf(address(this)) >= _distributedAmount + _referrerAmount,
            "Pool has not enough balance, your are too late"
        );

        TOKEN.transferWithoutFee(msg.sender, _distributedAmount);
        TOKEN.transferWithoutFee(_referrer, _referrerAmount);

        emit AirdropClaim(
            _nonce,
            _distributedAmount,
            _referrerAmount,
            msg.sender,
            _referrer
        );

        return true;
    }
}

