// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./ERC20_IERC20.sol";
import "./Ownable.sol";

contract DAO_Vault is Ownable {

    /* 10% DAO token allocation  */
    uint256 public immutable Max = 2000000000 ether;

    /* $MetaX Smart Contract */
    address public MetaX_addr;
    IERC20 public MX = IERC20(MetaX_addr);

    function setMetaX (address _MetaX_addr) public onlyOwner {
        require(!frozen, "DAO_Vault: $MetaX Tokens Address is frozen.");
        MetaX_addr = _MetaX_addr;
        MX = IERC20(_MetaX_addr);
    }

    /* Freeze $MetaX contract address for decentralization */
    bool public frozen;

    function setFrozen () public onlyOwner {
        frozen = true;
    }

    /* Initialization of $MetaX contract address */
    constructor (
        address _MetaX_addr
    ) {
        MetaX_addr = _MetaX_addr;
        MX = IERC20(_MetaX_addr);
    }

    /* DAO start @Sept 1st 2023 */
    uint256 public T0 = 1693526400;

    /* Accumulative tokens released from DAO */
    uint256 public accumReleased;

    /* Number of time tokens released from DAO */
    uint256 public numReleased;

    /* DAO release record */
    struct _releaseRecord {
        address receiver; /* Objects of release */
        uint256 timeReleased; /* Release timestamp */
        uint256 amountReleased; /* Release amount */
        string reason; /* Release reason */
    }

    /* Recording DAO release every time */
    mapping (uint256 => _releaseRecord) public releaseRecord;

    /* Check the balance of this vault */
    function Balance () public view returns (uint256) {
        return MX.balanceOf(address(this));
    }

    /* Release only by owner */
    function Release (address[] memory Receiver, uint256[] memory Amount, string[] memory Reason) public onlyOwner {
        require(block.timestamp > T0, "DAO_Vault: Please wait for open release.");
        require(Receiver.length == Amount.length && Receiver.length == Reason.length, "DAO_Vault: Incorrect inputs.");
        for (uint256 i=0; i<Receiver.length; i++) {
            require(Receiver[i] != address(0), "DAO_Vault: Can't release to address(0).");
            require(accumReleased + Amount[i] <= Max, "DAO_Vault: All the tokens have been released");
            numReleased ++;
            _releaseRecord storage record = releaseRecord[numReleased];
            accumReleased += Amount[i];
            record.receiver = Receiver[i];
            record.timeReleased = block.timestamp;
            record.amountReleased = Amount[i];
            record.reason = Reason[i];
            MX.transfer(Receiver[i], Amount[i]);
            emit DAORecord(Receiver[i], Amount[i], Reason[i], block.timestamp);
        }
    }

    event DAORecord(address receiver, uint256 amount, string reason, uint256 time);
}
