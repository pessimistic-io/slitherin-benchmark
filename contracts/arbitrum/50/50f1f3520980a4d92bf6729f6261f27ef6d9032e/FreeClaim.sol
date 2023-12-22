// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >0.8.0;

// @openzeppelin
import "./SafeERC20Upgradeable.sol";
import "./ECDSAUpgradeable.sol";

// Helpers
import "./BaseUpgradeable.sol";

import "./console.sol";

contract FreeClaim is BaseUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    event Claim(address indexed user, uint256 amount, uint256 timestamp);
    struct Information {
        uint256 currentClaimed;
        uint256 claimedCount;
        uint256 claimStart;
        uint256 claimOver;
        uint256 maxClaim;
    }

    // Verifiers
    address token;
    Information info;
    mapping(address => bool) verifiers;
    mapping(address => bool) public claimedUser;
    mapping(bytes32 => bool) public usedSignature;

    /**
     * @notice Checks if the msg.sender is a contract or a proxy
     */
    modifier notContract() {
        require(!_isContract(msg.sender), 'contract not allowed');
        require(msg.sender == tx.origin, 'proxy contract not allowed');
        _;
    }

    /** ======== Init ======== */
    function initialize(
        address _token,
        uint256 _claimStart,
        uint256 _claimOver,
        uint256 _maxClaim
    ) public initializer {
        __Base_init(); // also inits ownable
        verifiers[msg.sender] = true;

        info.claimOver = _claimOver;
        info.claimStart = _claimStart;
        info.maxClaim = _maxClaim;

        paused = true;

        token = _token;
    }

    function freeClaim(uint256 _amount, bytes memory _signature)
        external
        whenNotPaused
        notContract
    {
        require(info.claimStart < block.timestamp, 'Claim has not started');
        require(info.claimOver > block.timestamp, 'Claim Over');

        // Ensure valid signature
        bytes32 messageHash = sha256(abi.encode(msg.sender, _amount));
        require(!usedSignature[messageHash], 'Signature already used');

        address signedAddress = ECDSAUpgradeable.recover(messageHash, _signature);
        require(verifiers[signedAddress], 'Mint: Invalid Signature.');

        require(!claimedUser[msg.sender], 'Already Claimed');

        claimedUser[msg.sender] = true;
        usedSignature[messageHash] = true;

        info.currentClaimed += _amount;
        info.claimedCount++;

        require(info.maxClaim > info.currentClaimed, 'No more to claim');

        IERC20Upgradeable(token).safeTransfer(msg.sender, _amount);

        emit Claim(msg.sender, _amount, block.timestamp);
    }

    function setVerifier(address _verifier, bool _isVerifier) external onlyOwner {
        verifiers[_verifier] = _isVerifier;
    }

    function getInfo() external view returns (Information memory) {
        return info;
    }

    function getClaimed(address user) external view returns (bool) {
        return claimedUser[user];
    }

    /**
     * @notice Checks if address is a contract
     * @dev It prevents contract from being targetted
     */
    function _isContract(address addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }

    function setValues(uint256 _idx, uint256 _value) external onlyOwner {
        if (_idx == 0) info.claimStart = _value;
        else if (_idx == 1) info.claimOver = _value;
    }

    function setToken(address _token) external onlyOwner {
        token = _token;
    }

    /** @notice withdraw tokens stuck in contract */

    function rescueToken(address tokenAddress) external onlyOwner {
        IERC20Upgradeable(tokenAddress).transfer(
            msg.sender,
            IERC20Upgradeable(tokenAddress).balanceOf(address(this))
        );
    }

    function rescueEth() external onlyOwner {
        uint256 amountETH = address(this).balance;
        (bool success, ) = payable(msg.sender).call{value: amountETH}(new bytes(0));
        require(success, 'PEPEOHM: ETH_TRANSFER_FAILED');
    }
}

