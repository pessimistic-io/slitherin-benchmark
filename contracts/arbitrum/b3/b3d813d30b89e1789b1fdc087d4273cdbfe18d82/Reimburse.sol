// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./AccessControlEnumerableUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./PausableUpgradeable.sol";
import "./ERC20_IERC20Upgradeable.sol";
import "./Initializable.sol";
import "./MerkleProof.sol";
import "./IbDEI.sol";

contract Reimburse is
    Initializable,
    PausableUpgradeable,
    AccessControlEnumerableUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    bytes32 public constant WITHDRAWER_ROLE = keccak256("WITHDRAWER_ROLE");
    bytes32 public constant SETTER_ROLE = keccak256("SETTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    address public bDEI;
    address public usdc;
    address public deus;
    bytes32 public collateralMerkleRoot;
    bytes32 public deusMerkleRoot;
    uint256 public reimburseRatio; // decimals 1e6

    mapping(address => uint256) public claimedCollateralAmount;
    mapping(address => uint256) public claimedDeusAmount;

    uint256 public deiReimburseRatio;
    mapping(address => uint256) public claimableDeiAmount;
    mapping(address => uint256) public claimedDeiAmount;

    /*
    constructor() {
        _disableInitializers();
    }
    */

    function initialize(
        uint256 reimburseRatio_,
        address bDEI_,
        address usdc_,
        address deus_,
        address admin,
        address pauser,
        address setter
    ) public initializer {
        __Pausable_init();
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, pauser);
        _grantRole(SETTER_ROLE, setter);

        reimburseRatio = reimburseRatio_;
        bDEI = bDEI_;
        usdc = usdc_;
        deus = deus_;
    }

    function setCollateralMerkleRoot(
        bytes32 root
    ) external onlyRole(SETTER_ROLE) {
        collateralMerkleRoot = root;
    }

    function setDeusMerkleRoot(bytes32 root) external onlyRole(SETTER_ROLE) {
        deusMerkleRoot = root;
    }

    function setReimburseRatio(uint256 ratio) external onlyRole(SETTER_ROLE) {
        reimburseRatio = ratio;
    }

    function setDeiReimburseRatio(
        uint256 ratio
    ) external onlyRole(SETTER_ROLE) {
        require(ratio <= 1e6, "INVALID_RATIO");
        deiReimburseRatio = ratio;
    }

    event ClaimCollateral(
        address sender,
        uint256 amount,
        uint256 totalClaimableAmount,
        address to
    );

    function claimCollateral(
        uint256 amount,
        uint256 totalClaimableAmount,
        bytes32[] memory proof,
        address to
    ) external whenNotPaused {
        require(
            MerkleProof.verify(
                proof,
                collateralMerkleRoot,
                keccak256(abi.encode(msg.sender, totalClaimableAmount))
            ),
            "INVALID_PROOF"
        );
        require(
            amount + claimedCollateralAmount[msg.sender] <=
                totalClaimableAmount,
            "AMOUNT_TOO_HIGH"
        );
        require(to != address(0), "INVALID_TO_ADDRESS");

        claimedCollateralAmount[msg.sender] += amount;
        uint256 usdcAmount = (amount * reimburseRatio) / 1e6;

        require(usdcAmount >= 1e12, "ZERO_USDC_AMOUNT");

        uint256 bDEIAmount = amount - usdcAmount;
        IbDEI(bDEI).mint(to, bDEIAmount);
        IERC20Upgradeable(usdc).safeTransfer(to, usdcAmount / 1e12);

        emit ClaimCollateral(msg.sender, amount, totalClaimableAmount, to);
    }

    event ClaimDei(
        address sender,
        uint256 amount,
        uint256 totalClaimableAmount,
        address to
    );

    function claimDei(
        uint256 amount,
        uint256 totalClaimableAmount,
        bytes32[] memory proof,
        address to
    ) external whenNotPaused {
        require(
            MerkleProof.verify(
                proof,
                collateralMerkleRoot,
                keccak256(abi.encode(msg.sender, totalClaimableAmount))
            ),
            "INVALID_PROOF"
        );
        require(
            amount + claimedCollateralAmount[msg.sender] <=
                totalClaimableAmount,
            "AMOUNT_TOO_HIGH"
        );
        require(to != address(0), "Invalid to address");
        claimedCollateralAmount[msg.sender] += amount;
        uint256 deiAmount = (amount * deiReimburseRatio) / 1e6;
        uint256 bDEIAmount = amount - deiAmount;
        IbDEI(bDEI).mint(to, bDEIAmount);
        claimableDeiAmount[to] += deiAmount;
        emit ClaimDei(msg.sender, amount, totalClaimableAmount, to);
    }

    event ClaimDeus(
        address sender,
        uint256 amount,
        uint256 totalClaimableAmount,
        address to
    );

    function claimDeus(
        uint256 amount,
        uint256 totalClaimableAmount,
        bytes32[] memory proof,
        address to
    ) external whenNotPaused {
        require(
            MerkleProof.verify(
                proof,
                deusMerkleRoot,
                keccak256(abi.encode(msg.sender, totalClaimableAmount))
            ),
            "INVALID_PROOF"
        );
        require(
            amount + claimedDeusAmount[msg.sender] <= totalClaimableAmount,
            "AMOUNT_TOO_HIGH"
        );
        require(to != address(0), "INVALID_TO_ADDRESS");

        claimedDeusAmount[msg.sender] += amount;
        IERC20Upgradeable(deus).safeTransfer(to, amount);

        emit ClaimDeus(msg.sender, amount, totalClaimableAmount, to);
    }

    function pause() public onlyRole(PAUSER_ROLE) whenNotPaused {
        _pause();
    }

    function unpause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    // The following functions are overrides required by Solidity.
    function supportsInterface(
        bytes4 interfaceId
    ) public view override(AccessControlEnumerableUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function withdrawERC20(
        address token,
        uint256 amount,
        address to
    ) external onlyRole(WITHDRAWER_ROLE) {
        IERC20Upgradeable(token).safeTransfer(to, amount);
    }
}

