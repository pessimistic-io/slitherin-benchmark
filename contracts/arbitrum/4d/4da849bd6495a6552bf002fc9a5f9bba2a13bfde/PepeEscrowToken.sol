//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { ERC20 } from "./ERC20.sol";
import { IERC20 } from "./IERC20.sol";
import { Ownable2Step } from "./Ownable2Step.sol";
import { SafeERC20 } from "./SafeERC20.sol";

contract PepeEscrowToken is ERC20, Ownable2Step {
    using SafeERC20 for IERC20;
    uint128 private constant DECAY_RATIO = 1e16; //@dev 0.01% decay per day.
    uint48 private constant SECONDS_PER_DAY = 86400;
    uint48 public lastDecayTime;

    address public esPegStakingContract;
    address public esPegLockUpContract;

    event Retrieve(address indexed token, uint256 amount);
    event Decay(address[] indexed from);
    event Airdrop(address[] indexed to, uint256[] indexed amount);
    event StakingContractUpdated(address indexed stakingContract);
    event LockUpContractUpdated(address indexed lockUpContract);

    modifier onlyAuthorized() {
        require(
            msg.sender == owner() || msg.sender == esPegStakingContract || msg.sender == esPegLockUpContract,
            "!owner || !staking || !lockup"
        );
        _;
    }

    constructor(address esPegStakingContract_, address esPegLockUpContract_) ERC20("Pepe Escrow Token", "esPEG") {
        esPegStakingContract = esPegStakingContract_;
        esPegLockUpContract = esPegLockUpContract_;
    }

    ///@dev airdrop $esPeg tokens to users.
    function airdropEsPeg(address[] memory addrs, uint256[] calldata _amount) external onlyOwner {
        require(addrs.length == _amount.length, "Invalid input");
        uint256 length = addrs.length;
        uint64 i;

        for (; i < length; ) {
            _mint(addrs[i], _amount[i]);
            unchecked {
                ++i;
            }
        }
        // lastDecayTime = uint32(block.timestamp);

        emit Airdrop(addrs, _amount);
    }

    ///@notice burns the decayed tokens.
    ///decays the amount of user's unstaked or unlocked esPeg.
    function decay(address[] memory addrs) external onlyOwner {
        uint256 length = addrs.length;
        uint256 i;
        for (; i < length; ) {
            uint256 decayedAmount = calculateDecayAmount(addrs[i]);
            _burn(addrs[i], decayedAmount);

            unchecked {
                ++i;
            }
        }
        lastDecayTime = uint48(block.timestamp);
        emit Decay(addrs);
    }

    /**
     * @dev returns the amount to decay
     * per the number of seconds
     * @return -> decayfactor(the amount to burn).
     */
    function calculateDecayAmount(address _from) private view returns (uint256) {
        uint256 elapsedTime = block.timestamp - lastDecayTime;
        uint256 decayFactor = DECAY_RATIO * (elapsedTime / SECONDS_PER_DAY);
        return (balanceOf(_from) * decayFactor) / 1e18;
    }

    function updateStakingContract(address _stakingContract) external onlyOwner {
        esPegStakingContract = _stakingContract;
        emit StakingContractUpdated(_stakingContract);
    }

    function updateLockUpContract(address esPegLockUpContract_) external onlyOwner {
        esPegLockUpContract = esPegLockUpContract_;
        emit LockUpContractUpdated(esPegLockUpContract_);
    }

    function mint(address _account, uint256 amount) public onlyOwner {
        _mint(_account, amount);
    }

    function burn(address _from, uint256 _amount) external onlyAuthorized {
        require(_amount <= balanceOf(_from), "Insufficient Burn Amount");
        _burn(_from, _amount);
    }

    /// @dev retrieve stuck tokens
    function retrieve(address _token) external onlyOwner {
        require(_token != address(this), "Underlying Token");
        IERC20 token = IERC20(_token);
        if (address(this).balance != 0) {
            (bool success, ) = payable(owner()).call{ value: address(this).balance }("");
            require(success, "Retrieval Failed");
        }

        token.safeTransfer(owner(), token.balanceOf(address(this)));
    }
}

