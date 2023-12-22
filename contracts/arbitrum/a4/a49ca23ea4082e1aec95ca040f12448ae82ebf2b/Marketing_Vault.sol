// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./ERC20_IERC20.sol";
import "./Ownable.sol";

contract Marketing_Vault is Ownable {

    /* 10% Marketing token allocation */
    uint256 public immutable Max = 2000000000 ether;

    /* $MetaX smart contract */
    address public MetaX_addr;
    IERC20 public MX = IERC20(MetaX_addr);

    function setMetaX (address _MetaX_addr) public onlyOwner {
        require(!frozen, "Marketing_Vault: $MetaX Tokens Address is frozen.");
        MetaX_addr = _MetaX_addr;
        MX = IERC20(_MetaX_addr);
    }

    /* Initialization for $MetaX smart contract */
    constructor (
        address _MetaX_addr
    ) {
        MetaX_addr = _MetaX_addr;
        MX = IERC20(_MetaX_addr);
    }

    /* Freeze $MetaX contract address */
    bool public frozen;

    function setFrozen () public onlyOwner {
        frozen = true;
    }

    /* Marketing start @Sept 1st 2023 */
    uint256 public T0 = 1693526400;

    /* Accumulative tokens released from Marketing */
    uint256 public accumReleased;

    /* Number of time tokens released from Marketing */
    uint256 public numReleased;

    /* Marketing release record */
    struct _releaseRecord {
        address receiver; /* Objects of release */
        uint256 timeReleased; /* Release timestamp */
        uint256 amountReleased; /* Release amount */
    }

    /* Recording Marketing release every time */
    mapping (uint256 => _releaseRecord) public releaseRecord;

    /* Check the balance of this vault */
    function Balance () public view returns (uint256) {
        return MX.balanceOf(address(this));
    }
     
    /* Release only by owner */
    function Release (address Receiver, uint256 Amount) public onlyOwner {
        require(block.timestamp > T0, "Marketing_Vault: Please wait for open release.");
        require(accumReleased + Amount <= Max, "Marketing_Vault: All the tokens have been released");
        require(Receiver != address(0), "Marketing_Vault: Can't release to address(0).");
        numReleased ++;
        _releaseRecord storage record = releaseRecord[numReleased];
        accumReleased += Amount;
        record.receiver = Receiver;
        record.timeReleased = block.timestamp;
        record.amountReleased = Amount;
        MX.transfer(Receiver, Amount);
        emit marketingRecord(Receiver, Amount, block.timestamp);
    }

    event marketingRecord(address receiver, uint256 amount, uint256 time);
}
