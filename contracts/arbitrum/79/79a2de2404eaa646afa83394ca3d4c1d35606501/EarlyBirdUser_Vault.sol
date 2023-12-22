// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./ERC20_IERC20.sol";
import "./Ownable.sol";
import "./SafeMath.sol";

contract EarlyBirdUser_Vault is Ownable {
    using SafeMath for uint256;

    /* EarlyBird User token allocation */
    uint256 public immutable Max = 1090410948 ether;

    /* Initialization for $MetaX & EarlyBird User address */
    constructor (
        address _MetaX_addr,
        address _earlyBirdUser_addr
    ) {
        MetaX_addr = _MetaX_addr;
        MX = IERC20(_MetaX_addr);
        earlyBirdUser_addr = _earlyBirdUser_addr;
    }

    /* $MetaX Smart Contract */
    address public MetaX_addr;
    IERC20 public MX = IERC20(MetaX_addr);

    function setMetaX (address _MetaX_addr) public onlyOwner {
        require(!frozenToken, "EarlyBirdUser_Vault: $MetaX Tokens Address is frozen.");
        MetaX_addr = _MetaX_addr;
        MX = IERC20(_MetaX_addr);
    }

    /* Freeze the $MetaX contract */
    bool public frozenToken;

    function setFrozenToken () public onlyOwner {
        frozenToken = true;
    }

    /* EarlyBird User contract */
    address public earlyBirdUser_addr;

    function setEarlyBirdUser (address _earlyBirdUser_addr) public onlyOwner {
        require(!frozenEarlyBirdUser, "EarlyBirdUser_Vault: EarlyBirdUser Address is frozen.");
        earlyBirdUser_addr = _earlyBirdUser_addr;
    }

    /* Freeze the EarlyBird User address */
    bool public frozenEarlyBirdUser;

    function setFrozenEarlyBirdUser () public onlyOwner {
        frozenEarlyBirdUser = true;
    }
    
    /* EarlyBird User release start @Sept 1st 2023 */
    uint256 public immutable T0 = 1693526400;

    /* EarlyBird User initialization end @Oct 1st 2023 */
    uint256 public immutable T1 = 1696118400;

    /* Track for accumulative release in $MetaX */
    uint256 public accumRelease;

    /* Track for the number of time release */
    uint256 public numRelease;

    /* Check the balance of this vault */
    function Balance () public view returns (uint256) {
        return MX.balanceOf(address(this));
    }

    /* Recording every release */
    struct _releaseRecord {
        address receiver;
        uint256 amount;
        uint256 time;
        string action;
    }

    /* Reference of every release */
    mapping (uint256 => _releaseRecord) public releaseRecord;

    /* Release to EarlyBird User address only by owner */
    function Release (uint256 release, string memory action) public onlyOwner {
        require(block.timestamp > T0, "EarlyBirdUser_Vault: Please wait for EarlyBird user open.");
        require(accumRelease + release <= Max, "EarlyBirdUser_Vault: All the tokens have been released.");
        require(earlyBirdUser_addr != address(0), "EarlyBirdUser_Vault: Can't release to address(0).");
        MX.transfer(earlyBirdUser_addr, release);
        accumRelease += release;
        numRelease ++;
        releaseRecord[numRelease] = _releaseRecord(earlyBirdUser_addr, release, block.timestamp, action);
    }

    /* Burn address */
    address public immutable Burn_addr = 0x000000000000000000000000000000000000dEaD;

    /* Burn extra EarlyBird User tokens */
    function Burn (string memory action) public onlyOwner {
        require(block.timestamp > T1, "EarlyBirdUser_Vault: Please wait till the EarlyBird initialization period is over");
        uint256 amount = Balance();
        MX.transfer(Burn_addr, amount);
        accumRelease += amount;
        numRelease ++;
        releaseRecord[numRelease] = _releaseRecord(Burn_addr, amount, block.timestamp, action);
    }

}
