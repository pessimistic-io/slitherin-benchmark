// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./SignatureCheckerUpgradeable.sol";

contract Airdrop is UUPSUpgradeable, OwnableUpgradeable{
    using SignatureCheckerUpgradeable for address;
    IERC20Upgradeable public token;
    address private _signer; 

    uint256 public constant MAX_ADDRESSES_ARB = 200000;
    uint256 public constant MAX_ADDRESSES_PEPE = 40000;
    uint256 public constant MAX_TOKEN_ARB = 126_000_000_000_000_000 * 1e6;
    uint256 public constant MAX_TOKEN_PEPE = 54_000_000_000_000_000 * 1e6;
    uint256 public constant USER_PER_ROUND_ARB = 20000;
    uint256 public constant USER_PER_ROUND_PEPE = 3000;
    uint256 public constant INIT_PERCENT = 190;
    uint256 public constant DENOMINATOR = 1000;

    struct Info {
        uint256 maxToken;
        uint256 initPercent;
        uint256 userPerRound;
        uint256 currentClaim;
        bool claimed;
        uint256 inviteRewards;
        uint256 inviteUsers;
        uint256 claimedSupply;
        uint256 claimedCount;
    }

    event Claim(
        address indexed user, 
        string internalId, 
        uint256 amount, 
        address referrer, 
        uint timestamp
    );

    mapping(string => bool) public usedInternalId;
    mapping(address => bool) public claimedUserARB;
    mapping(address => bool) public claimedUserPEPE;
    mapping(address => uint256) public inviteRewardsARB;
    mapping(address => uint256) public inviteRewardsPEPE;
    mapping(address => uint256) public inviteUsersARB;
    mapping(address => uint256) public inviteUsersPEPE;

    uint256 public claimedSupplyARB;
    uint256 public claimedCountARB;
    uint256 public claimedPercentageARB;

    uint256 public claimedSupplyPEPE;
    uint256 public claimedCountPEPE;
    uint256 public claimedPercentagePEPE;

    

    ///@dev required by the OZ UUPS module
    function _authorizeUpgrade(address) internal override onlyOwner {}

    function initialize( address token_) external initializer {
        __Ownable_init();
        token = IERC20Upgradeable(token_);
        claimedSupplyARB = 0;
        claimedCountARB = 0;
        claimedPercentageARB = 0;

        claimedSupplyPEPE = 0;
        claimedCountPEPE = 0;
        claimedPercentagePEPE = 0;
    }

    function canClaimAmountARB() public view returns(uint256) {
        
        if (claimedCountARB >= MAX_ADDRESSES_ARB) {
            return 0;
        }

        uint256 supplyPerAddress = MAX_TOKEN_ARB * INIT_PERCENT / DENOMINATOR / USER_PER_ROUND_ARB;
        uint256 curClaimedCount = claimedCountARB + 1;
        uint256 claimedPercent = curClaimedCount * 100e6 / MAX_ADDRESSES_ARB;
        uint256 curPercent = 10e6;
        uint256 percent = INIT_PERCENT;
        while (curPercent < claimedPercent) {
            if (curPercent == 10e6) {
                percent = percent - 40;
                supplyPerAddress = MAX_TOKEN_ARB * percent / DENOMINATOR / USER_PER_ROUND_ARB;
            } else {
                percent = percent - 15;
                if (percent <=0 ){
                    return 0;
                }
                supplyPerAddress = MAX_TOKEN_ARB * percent / DENOMINATOR / USER_PER_ROUND_ARB;
            }
            
            curPercent += 10e6;
        }

        return supplyPerAddress;
    }
    function claimARB(string memory internalId, bytes calldata signature, address referrer) public {
        require(usedInternalId[internalId] == false, "ARB Airdrop: nonce already used");
        require(claimedUserARB[_msgSender()] == false, "ARB Airdrop: already claimed");

        claimedUserARB[_msgSender()] = true;
        bytes32 message = keccak256(abi.encode(address(this), _msgSender(), internalId));

        _signer.isValidSignatureNow(message,signature);
        usedInternalId[internalId] = true;

        uint256 supplyPerAddress = canClaimAmountARB();
        require(supplyPerAddress >= 1e6, "ARB Airdrop: Airdrop has ended");

        uint256 amount = canClaimAmountARB();
        token.transfer(_msgSender(), amount);

        claimedCountARB++;
        claimedSupplyARB += supplyPerAddress;

        if (claimedCountARB > 0) {
            claimedPercentageARB = (claimedCountARB * 100) / MAX_ADDRESSES_ARB;
        }

        if (referrer != address(0) && referrer != _msgSender()) {
            uint256 num = amount * 100 / 1000;
            token.transfer(referrer, num);
            inviteRewardsARB[referrer] += num;
            inviteUsersARB[referrer]++;
        }

        emit Claim(_msgSender(), internalId, amount, referrer, block.timestamp);
    }

    function canClaimAmountPEPE() public view returns(uint256) {
        
        if (claimedCountPEPE >= MAX_ADDRESSES_PEPE) {
            return 0;
        }

        uint256 supplyPerAddress = MAX_TOKEN_PEPE * INIT_PERCENT / DENOMINATOR / USER_PER_ROUND_PEPE;
        uint256 curClaimedCount = claimedCountPEPE + 1;
        uint256 claimedPercent = curClaimedCount * 100e6 / MAX_ADDRESSES_PEPE;
        uint256 curPercent = 10e6;
        uint256 percent = INIT_PERCENT;

        while (curPercent < claimedPercent) {
            if (curPercent == 10e6) {
                percent = percent - 40;
                supplyPerAddress = MAX_TOKEN_PEPE * percent / DENOMINATOR / USER_PER_ROUND_PEPE;
            } else {
                percent = percent - 15;
                if (percent <=0 ){
                    return 0;
                }
                supplyPerAddress = MAX_TOKEN_PEPE * percent / DENOMINATOR / USER_PER_ROUND_PEPE;
            }
            
            curPercent += 10e6;
        }

        return supplyPerAddress;
    }
    function claimPEPE(string memory internalId, bytes calldata signature, address referrer) public {
        require(usedInternalId[internalId] == false, "PEPE Airdrop: nonce already used");
        require(claimedUserPEPE[_msgSender()] == false, "PEPE Airdrop: already claimed");

        claimedUserPEPE[_msgSender()] = true;
        bytes32 message = keccak256(abi.encode(address(this), _msgSender(), internalId));

        _signer.isValidSignatureNow(message,signature);
        usedInternalId[internalId] = true;

        uint256 supplyPerAddress = canClaimAmountPEPE();
        require(supplyPerAddress >= 1e6, "PEPE Airdrop: Airdrop has ended");

        uint256 amount = canClaimAmountPEPE();
        token.transfer(_msgSender(), amount);

        claimedCountPEPE++;
        claimedSupplyPEPE += supplyPerAddress;

        if (claimedCountPEPE > 0) {
            claimedPercentagePEPE = (claimedCountPEPE * 100) / MAX_ADDRESSES_PEPE;
        }

        if (referrer != address(0) && referrer != _msgSender()) {
            uint256 num = amount * 100 / 1000;
            token.transfer(referrer, num);
            inviteRewardsPEPE[referrer] += num;
            inviteUsersPEPE[referrer]++;
        }

        emit Claim(_msgSender(), internalId, amount, referrer, block.timestamp);
    }

    function getInfoARBAirdrop(address user) public view returns(Info memory) {
        return Info({
            maxToken: MAX_ADDRESSES_ARB,
            initPercent: INIT_PERCENT,
            userPerRound: USER_PER_ROUND_ARB,
            currentClaim: canClaimAmountARB(),
            claimed: claimedUserARB[user],
            inviteRewards: inviteRewardsARB[user],
            inviteUsers: inviteUsersARB[user],
            claimedSupply: claimedSupplyARB,
            claimedCount: claimedCountARB
        });
    }
    function getInfoPEPEAirdrop(address user) public view returns(Info memory) {
        return Info({
            maxToken: MAX_ADDRESSES_PEPE,
            initPercent: INIT_PERCENT,
            userPerRound: USER_PER_ROUND_PEPE,
            currentClaim: canClaimAmountPEPE(),
            claimed: claimedUserPEPE[user],
            inviteRewards: inviteRewardsPEPE[user],
            inviteUsers: inviteUsersPEPE[user],
            claimedSupply: claimedSupplyPEPE,
            claimedCount: claimedCountPEPE
        });
    }

    function updateSigner(address val) external onlyOwner(){
        require(val != address(0), "val is the zero address");
        _signer = val;
    }

    function getSigners() public view returns (address) {
        return _signer;
    }

}
