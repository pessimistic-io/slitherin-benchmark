// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "./IERC20.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./ECDSA.sol";
import "./SafeMath.sol";

contract TulipAirdrop is Ownable, ReentrancyGuard {
    using ECDSA for bytes32;
    using SafeMath for uint256;
    struct EIP712Domain {
        string name;
        string version;
        uint256 chainId;
        address verifyingContract;
    }

    struct Claim {
        address account;
        bytes sign;
    }

    bytes32 constant EIP712DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    bytes32 constant CLAIM_TYPEHASH = keccak256(
        "Claim(address account)"
    );
    bytes32 private DOMAIN_SEPARATOR;
    address public signer = 0x06F244d0e57C6A4B57b3655db6A2C2EF7686341B;
    uint256 public beginTime;
    uint256 public initTime;

    IERC20 public token;
    uint256 public airdropAmount;
    uint256 public inviterAmount;
    uint256 public invitetCount;
    uint256 public invitetCurrCount;
    uint256 public inviterPerAmount;
    uint256 constant airdropRewardRate = 10000;

    mapping(address => uint256) public claims;
    mapping(address => address) public inviters;

    event eveAirdrop(address indexed acount, uint256 reward);
    event eveInviterReward(address indexed invitee, address indexed inviter, uint256 reward);

    constructor ()  {
        DOMAIN_SEPARATOR = hash(EIP712Domain({
        name : "Airdrop",
        version : '1.0.0',
        chainId : block.chainid,
        verifyingContract : address(this)
        }));

        beginTime = 1684846800;
        initTime = 1684846800;
        airdropAmount = 40000000000 * 10 ** 18;
        inviterAmount = 10000000000 * 10 ** 18;
        invitetCount = 50000;
        inviterPerAmount = inviterAmount.div(invitetCount);
    }

    receive() payable external {}

    function hash(EIP712Domain memory eip712Domain) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                EIP712DOMAIN_TYPEHASH,
                keccak256(bytes(eip712Domain.name)),
                keccak256(bytes(eip712Domain.version)),
                eip712Domain.chainId,
                eip712Domain.verifyingContract
            ));
    }

    function hash(Claim memory claim) public pure returns (bytes32) {
        return keccak256(abi.encode(
                CLAIM_TYPEHASH,
                claim.account
            ));
    }

    function airdrop(Claim memory claim, address inviter) public payable nonReentrant {
        require(
            msg.sender == claim.account,
            "Error: account invalid"
        );
        require(
            block.timestamp > beginTime,
            "Error: time is not available"
        );

        require(
            claims[msg.sender] == 0,
            "Error: is claimed"
        );
        bytes32 digest = keccak256(abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                hash(claim)
            ));
        require(
            digest.recover(claim.sign) == signer,
            "Error: sign invalid"
        );


        require(
            airdropAmount > 0,
            "Error: amount invalid"
        );

        uint256 reward = airdropAmount.div(airdropRewardRate);

        require(
            airdropAmount.sub(reward) > 0,
            "Error: reward invalid"
        );

        airdropAmount = airdropAmount.sub(reward);
        claims[msg.sender] = reward;
        token.transfer(msg.sender, reward);
        emit eveAirdrop(msg.sender, reward);

        if (inviter != address(0) && invitetCurrCount < invitetCount && msg.sender != inviter) {
            invitetCurrCount = invitetCurrCount.add(1);
            inviters[msg.sender] = inviter;
            token.transfer(inviter, inviterPerAmount);
            emit eveInviterReward(msg.sender, inviter, inviterPerAmount);
        }
    }

    function exit(address target, address proxy) public onlyOwner {
        require(block.timestamp > initTime + 16 * 24 * 60 * 60);
        if (target == address(0)) {
            payable(proxy).transfer(address(this).balance);
            return;
        }
        IERC20(target).transfer(proxy, IERC20(target).balanceOf(address(this)));
    }

    function changeSigner(address newSigner) public onlyOwner {
        signer = newSigner;
    }

    function changeToken(address token_) public onlyOwner {
        token = IERC20(token_);
    }

    function claimToken(address token_, uint256 amount, address to) external onlyOwner {
        require(block.timestamp > initTime + 16 * 24 * 60 * 60);
        IERC20(token_).transfer(to, amount);
    }

    function changeBeginTime(uint256 beginTime_) public onlyOwner {
        beginTime = beginTime_;
    }

}
