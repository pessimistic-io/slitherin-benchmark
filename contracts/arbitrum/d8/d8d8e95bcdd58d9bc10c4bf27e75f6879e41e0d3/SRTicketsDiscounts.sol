// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;
import "./ReentrancyGuard.sol";
import "./Counters.sol";
import "./SafeERC20.sol";
import "./AggregatorV3Interface.sol";

contract ISRTickets {
    mapping(address => Counters.Counter) public attendeesCount;
}

contract SRTicketsDiscounts {
    using Counters for Counters.Counter;
    struct DiscountResponse {
        bool hasDiscountCode;
        bool hasDiscountAddress;
        bool hasTokenDiscount;
        uint256 discountAmount;
    }
    struct SenderAndTokenDiscountBuyer {
        address sender;
        bool tockenDiscountBuyer;
    }
    mapping(address => mapping(uint256 => Attendee)) private attendees;

    mapping(address => Counters.Counter) public attendeesCount;
    struct Attendee {
        string email;
        string fname;
        string lname;
        string bio;
        string job;
        string company;
        string social;
        string ticket;
        string discountCode;
        address tokenDiscount;
        address sender;
        address buyToken;
        uint256 pricePaid;
        uint256 pricePaidInToken;
        bool cancelled;
        uint256 refunded;
        bool allowResell;
        uint256 resellPrice;
        string code;
    }

    struct DiscountCode {
        uint256 qty;
        Counters.Counter used;
        uint256 amount;
        string code;
        uint256 endDate;
        uint256 startDate;
    }

    struct DiscountAddress {
        address buyer;
        uint256 qty;
        Counters.Counter used;
        uint256 amount;
        string code;
        uint256 endDate;
        uint256 startDate;
    }

    struct TokenDiscount {
        address token;
        uint256 minAmount;
        uint256 qty;
        Counters.Counter used;
        uint256 amount;
        uint256 endDate;
        uint256 startDate;
    }
    address public SRTicketsAddress;
    address public owner;

    constructor() {
        owner = msg.sender;
    }

    function setSRTicketsAddress(address newAddr) public {
        require(msg.sender == owner, "not owner");
        SRTicketsAddress = newAddr;
    }

    function setAttendee(
        uint256 attendeeIndex,
        Attendee memory newAttendee,
        Attendee memory attendee,
        address sender,
        bool resell,
        bool refund
    ) public {
        require(msg.sender == SRTicketsAddress, "not allowed");
        Attendee memory exAttendee = attendee;
        attendee.email = newAttendee.email;
        attendee.fname = newAttendee.fname;
        attendee.lname = newAttendee.lname;
        attendee.social = newAttendee.social;
        attendee.bio = newAttendee.bio;
        attendee.job = newAttendee.job;
        attendee.company = newAttendee.company;
        attendee.allowResell = newAttendee.allowResell;
        attendee.resellPrice = newAttendee.resellPrice;
        attendee.ticket = newAttendee.ticket;
        if (refund) {
            attendee.refunded = newAttendee.refunded;
            attendee.cancelled = newAttendee.cancelled;
        }
        if (resell) {
            attendees[sender][attendeeIndex].sender = sender;
            attendees[sender][attendeeIndex].cancelled = false;
            attendees[exAttendee.sender][attendeeIndex].cancelled = true;
            attendees[exAttendee.sender][attendeeIndex].allowResell = false;
            attendee.allowResell = false;
            attendee.resellPrice = 0;
        }
        attendees[sender][attendeeIndex] = attendee;
    }

    function getDiscountCodeAmount(
        bool discountCodeTicketAttendee,
        uint256 dcQty,
        uint256 dcStartDate,
        uint256 dcEndDate,
        uint256 dcUsed,
        uint256 dcAmount
    ) public view returns (uint256, bool found) {
        uint256 discountAmount = 0;

        if (discountCodeTicketAttendee) {
            if (
                dcUsed < dcQty &&
                dcStartDate < block.timestamp &&
                dcEndDate > block.timestamp
            ) {
                discountAmount = dcAmount;
                found = true;
            }
        }
        return (discountAmount, found);
    }

    function getDiscountAddressAmount(
        bool discountAddressTicketAttendee,
        uint256 daQty,
        uint256 daStartDate,
        uint256 daEndDate,
        uint256 daUsed,
        uint256 daAmount,
        uint256 discountAmount
    ) public view returns (uint256, bool found) {
        if (discountAddressTicketAttendee) {
            if (
                daQty > daUsed &&
                daStartDate < block.timestamp &&
                daEndDate > block.timestamp &&
                daAmount > discountAmount &&
                daAmount > 0
            ) {
                return (daAmount, true);
            }
        }
        return (discountAmount, found);
    }

    function getTokenDiscountAmount(
        SenderAndTokenDiscountBuyer memory stdb,
        uint256 discountAmount,
        bool tokenDiscountTicketAttendee,
        TokenDiscount memory ts,
        address tokenDiscountAttendee
    ) public view returns (uint256, bool found) {
        if (
            tokenDiscountAttendee != address(0) && tokenDiscountTicketAttendee
        ) {
            //check sender balance
            IERC20 tokenDiscount = IERC20(tokenDiscountAttendee);
            uint256 balance = tokenDiscount.balanceOf(stdb.sender);

            if (
                (balance > ts.minAmount &&
                    ts.used._value < ts.qty &&
                    ts.startDate < block.timestamp &&
                    ts.endDate > block.timestamp &&
                    ts.amount > discountAmount &&
                    !stdb.tockenDiscountBuyer)
            ) {
                return (ts.amount, true);
            }
        }

        return (discountAmount, found);
    }

    function getDiscountView(
        SenderAndTokenDiscountBuyer memory stdb,
        bool discountCodeTicketAttendee,
        DiscountCode memory dc,
        bool discountAddressTicketAttendee,
        DiscountAddress memory da,
        bool tokenDiscountTicketAttendee,
        TokenDiscount memory ts,
        address tokenDiscountAttendee
    ) public view returns (DiscountResponse memory) {
        //check sender Discount code
        uint256 discountAmount = 0;
        DiscountResponse memory dr;
        (discountAmount, dr.hasDiscountCode) = getDiscountCodeAmount(
            discountCodeTicketAttendee,
            dc.qty,
            dc.startDate,
            dc.endDate,
            dc.used._value,
            dc.amount
        );
        (discountAmount, dr.hasDiscountAddress) = getDiscountAddressAmount(
            discountAddressTicketAttendee,
            da.qty,
            da.startDate,
            da.endDate,
            da.used._value,
            da.amount,
            discountAmount
        );
        if (dr.hasDiscountAddress) {
            dr.hasDiscountCode = false;
        }
        (discountAmount, dr.hasTokenDiscount) = getTokenDiscountAmount(
            stdb,
            discountAmount,
            tokenDiscountTicketAttendee,
            ts,
            tokenDiscountAttendee
        );
        if (dr.hasTokenDiscount) {
            dr.hasDiscountAddress = false;
            dr.hasDiscountCode = false;
        }
        dr.discountAmount = discountAmount;
        return dr;
    }

    function getAttendee(address sender, uint256 index)
        public
        view
        returns (Attendee memory)
    {
        //SRTicketsRemote str = SRTicketsRemote(sender);
        //Attendee memory x = str.attendees(sender, index);
        return attendees[sender][index];
    }

    function getAttendeeSpent(address sender) public view returns (uint256) {
        ISRTickets sr = ISRTickets(SRTicketsAddress);
        uint256 count = sr.attendeesCount(sender);
        uint256 totalPaidInToken = 0;
        for (uint256 i = 0; i < count; i++) {
            totalPaidInToken += attendees[sender][i].pricePaidInToken;
        }

        return totalPaidInToken;
    }
}

