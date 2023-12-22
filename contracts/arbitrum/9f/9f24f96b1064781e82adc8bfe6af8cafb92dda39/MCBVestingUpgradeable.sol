// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.4;

import "./ReentrancyGuardUpgradeable.sol";
import "./SafeMathUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./Initializable.sol";

contract MCBVestingUpgradeable is Initializable, ReentrancyGuardUpgradeable, OwnableUpgradeable {
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    string public constant name = "MCBVesting";
    address public constant MCB_TOKEN_ADDRESS = 0x4e352cF164E64ADCBad318C3a1e222E9EBa4Ce42;

    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    /// @notice The EIP-712 typehash for the delegation struct used by the contract
    bytes32 public constant UPDATE_BENEFICIARY_TYPEHASH =
        keccak256(
            "UpdateBeneficiary(address oldBeneficiary,address newBeneficiary,uint256 nonce,uint256 expiration)"
        );

    struct TokenBalance {
        uint96 remaining;
        uint96 cumulative;
    }

    struct VestingAccount {
        uint96 claimed;
        uint96 cumulativeRef;
        uint96 commitment;
    }

    uint96 public totalCommitment;
    uint256 public beginTime;

    TokenBalance public tokenBalance;
    mapping(address => VestingAccount) public accounts;
    mapping(address => uint256) public nonces;

    event Claim(address indexed beneficiary, uint96 amount);
    event AddBeneficiaries(address[] beneficiaries, uint96[] amounts);
    event UpdateBeneficiary(address indexed oldBeneficiary, address indexed newBeneficiary);

    function initialize(
        uint256 beginTime_,
        address[] memory beneficiaries_,
        uint96[] memory amounts_
    ) external initializer {
        require(beneficiaries_.length == amounts_.length, "length of parameters are not match");

        __ReentrancyGuard_init();
        __Ownable_init();

        beginTime = beginTime_;

        uint96 totalCommitment_;
        for (uint256 i = 0; i < beneficiaries_.length; i++) {
            (address beneficiary, uint96 amount) = (beneficiaries_[i], amounts_[i]);
            require(beneficiary != address(0), "beneficiary cannot be zero address");
            require(amount != 0, "amount cannot be zero");
            accounts[beneficiary] = VestingAccount({
                commitment: amount,
                cumulativeRef: 0,
                claimed: 0
            });
            totalCommitment_ = _add96(totalCommitment_, _safe96(amount));
        }
        totalCommitment = totalCommitment_;
        emit AddBeneficiaries(beneficiaries_, amounts_);
    }

    /**
     * @notice  Update beneficiary address and claiming status.
     */
    function updateBeneficiary(address oldBeneficiary, address newBeneficiary) external onlyOwner {
        _updateBeneficiary(oldBeneficiary, newBeneficiary);
    }

    /**
     * @notice  Update beneficiary address and claiming status for a signed request.
     */
    function updateBeneficiaryBySignature(
        address oldBeneficiary,
        address newBeneficiary,
        uint256 nonce,
        uint256 expiration,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        bytes32 domainSeparator = keccak256(
            abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name)), _chainId(), address(this))
        );
        bytes32 structHash = keccak256(
            abi.encode(
                UPDATE_BENEFICIARY_TYPEHASH,
                oldBeneficiary,
                newBeneficiary,
                nonce,
                expiration
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        address signer = ecrecover(digest, v, r, s);
        require(signer != address(0), "invalid signature");
        require(nonce == nonces[signer], "invalid nonce");
        require(block.timestamp <= expiration, "signature expired");
        require(oldBeneficiary == signer, "signer is not the old beneficiary");

        _updateBeneficiary(oldBeneficiary, newBeneficiary);
        nonces[signer]++;
    }

    function commitments(address beneficiary) public view returns (uint96) {
        return accounts[beneficiary].commitment;
    }

    function claimedBalances(address beneficiary) public view returns (uint96) {
        return accounts[beneficiary].claimed;
    }

    /**
     * @notice  The share of commitment amount in total amount. The value will not change during vesting.
     */
    function shareOf(address beneficiary) public view returns (uint96) {
        return _wdivFloor96(accounts[beneficiary].commitment, totalCommitment);
    }

    /**
     * @notice  The amount can be claimed for an account.
     */
    function claimableToken(address beneficiary) external view returns (uint256) {
        (uint96 claimable, ) = _claimableToken(beneficiary);
        return claimable;
    }

    /**
     * @notice  Claim token.
     */
    function claim() external nonReentrant {
        address beneficiary = msg.sender;
        require(_blockTimestamp() >= beginTime, "claim is not active now");
        (uint96 claimable, uint96 cumulativeReceived) = _claimableToken(beneficiary);
        require(claimable > 0, "no token to claim");
        VestingAccount storage account = accounts[beneficiary];
        account.claimed = _add96(account.claimed, claimable);
        account.cumulativeRef = cumulativeReceived;
        _mcbToken().safeTransfer(beneficiary, claimable);
        tokenBalance.remaining = _safe96(_mcbBalance());
        tokenBalance.cumulative = cumulativeReceived;

        emit Claim(beneficiary, claimable);
    }

    function _claimableToken(address beneficiary)
        internal
        view
        returns (uint96 claimable, uint96 cumulativeReceived)
    {
        // get received token tokenBalance
        uint96 incrementalReceived = _sub96(_safe96(_mcbBalance()), tokenBalance.remaining);
        cumulativeReceived = _add96(tokenBalance.cumulative, incrementalReceived);
        // calc claimable of beneficiary
        VestingAccount storage account = accounts[beneficiary];
        uint96 vested = _wmul96(cumulativeReceived, shareOf(beneficiary));
        if (vested <= account.claimed) {
            claimable = 0;
            return (claimable, cumulativeReceived);
        }
        uint96 maxUnclaimed = _sub96(account.commitment, account.claimed);
        if (maxUnclaimed != 0 && cumulativeReceived > account.cumulativeRef) {
            claimable = _sub96(cumulativeReceived, account.cumulativeRef);
            claimable = _wmul96(claimable, shareOf(beneficiary));
            claimable = claimable < maxUnclaimed ? claimable : maxUnclaimed;
        } else {
            claimable = 0;
        }
    }

    function _updateBeneficiary(address oldBeneficiary, address newBeneficiary) internal {
        require(newBeneficiary != address(0), "new beneficiary is zero address");
        VestingAccount storage oldAccount = accounts[oldBeneficiary];
        VestingAccount storage newAccount = accounts[newBeneficiary];
        require(oldAccount.commitment > 0, "old beneficiary has no commitments");
        require(newAccount.commitment == 0, "new beneficiary must has no commitments");
        require(
            oldAccount.claimed != oldAccount.commitment,
            "old beneficiary has no more token to claim"
        );

        newAccount.commitment = oldAccount.commitment;
        newAccount.cumulativeRef = oldAccount.cumulativeRef;
        newAccount.claimed = oldAccount.claimed;
        oldAccount.commitment = 0;
        oldAccount.cumulativeRef = 0;
        oldAccount.claimed = 0;

        emit UpdateBeneficiary(oldBeneficiary, newBeneficiary);
    }

    function _mcbBalance() internal view virtual returns (uint96) {
        return _safe96(_mcbToken().balanceOf(address(this)));
    }

    function _mcbToken() internal view virtual returns (IERC20Upgradeable) {
        return IERC20Upgradeable(MCB_TOKEN_ADDRESS);
    }

    function _blockTimestamp() internal view virtual returns (uint256) {
        return block.timestamp;
    }

    // math libs
    function _add96(uint96 a, uint96 b) internal pure returns (uint96) {
        uint96 c = a + b;
        require(c >= a, "addition overflow");
        return c;
    }

    function _sub96(uint96 a, uint96 b) internal pure returns (uint96) {
        require(b <= a, "subtraction overflow");
        return a - b;
    }

    function _safe96(uint256 n) internal pure returns (uint96) {
        return _safe96(n, "conversion to uint96 overflow");
    }

    function _safe96(uint256 n, string memory errorMessage) internal pure returns (uint96) {
        require(n < 2**96, errorMessage);
        return uint96(n);
    }

    function _wmul96(uint256 x, uint256 y) internal pure returns (uint96 z) {
        z = _safe96(x.mul(y) / 1e18, "multiplication overflow");
    }

    function _wdivFloor96(uint256 x, uint256 y) internal pure returns (uint96 z) {
        z = _safe96(x.mul(1e18).div(y), "division overflow");
    }

    function _chainId() internal pure returns (uint256) {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        return chainId;
    }
}

