// SPDX-License-Identifier: MIT

//   /$$                                               /$$$$$$$$ /$$$$$$$$ /$$   /$$
//  | $$                                              | $$_____/|__  $$__/| $$  | $$
//  | $$        /$$$$$$   /$$$$$$   /$$$$$$  /$$$$$$$ | $$         | $$   | $$  | $$
//  | $$       /$$__  $$ |____  $$ /$$__  $$| $$__  $$| $$$$$      | $$   | $$$$$$$$
//  | $$      | $$$$$$$$  /$$$$$$$| $$  \__/| $$  \ $$| $$__/      | $$   | $$__  $$
//  | $$      | $$_____/ /$$__  $$| $$      | $$  | $$| $$         | $$   | $$  | $$
//  | $$$$$$$$|  $$$$$$$|  $$$$$$$| $$      | $$  | $$| $$$$$$$$   | $$   | $$  | $$
//  |________/ \_______/ \_______/|__/      |__/  |__/|________/   |__/   |__/  |__/

// @DEV: QAZIPOLO.ETH // ------------------------------------------------------------- //                                                                              

pragma solidity ^0.8.17;

import "./ERC721.sol";
import "./Ownable.sol";
import "./Strings.sol";
import "./SafeMath.sol";
import "./Base64.sol";

contract LearnETH is ERC721, Ownable {
    using SafeMath for uint256;
    using Strings for uint256;
    uint256 private _tokenIdCounter;
    uint256 public partnerFee;

    bool private initiated;
    address private topNodeWallet;
    uint256 private monthDuration = 2592000;
	
    uint256 public currentPartnerCourseId;
    
    // nodeType 0 = Student
    // nodeType 1 = Instructor
    // nodeType 2 = Partner
    // nodeType 3 = Special A Partner
    // nodeType 4 = Special B Partner
    // nodeType 5 = Special A (Top node)
    
    struct node {
        uint8 nodeType;
        uint256 level; // starts with 1
        uint256 position; //starts with 1
        uint256 father1;
        uint256 personalReferrer;
        uint256 balance;
        uint256 subscribedTill;
        uint256 totalRecruits;
        uint256 lastSaleAt;
    }

    uint256 private courseIndex;

    struct course {
        string courseName;
        uint256 courseFee;
        uint256 instructorTokenId;
    }

    uint256 private partnerCourseIndex;

    struct partnerCourse {
        string courseName;
        uint256 courseFee;
        uint256 instructorTokenId;
        uint256 balance;
        bool claimable;
    }

    uint256 private paymentIndex;

    struct fee {
        uint256 paidBy;
        uint256 paidTo;
        uint256 paidFor;
        uint256 paidAmount;
        uint256 paidAt;
        uint status; // 0 - locked; 1 - distributed; 2 - refunded
    }
	
	struct earnings {
        uint256 tokenId;
        uint256 amount;
    }

    // [tokenId] => struct node
    mapping(uint256 => node) public nodeDetails;
    // [level][position] => tokenId
    mapping(uint256 => mapping(uint256 => uint256)) public partnerNodeTokenMapping;
    // [courseId] => struct course
    mapping(uint256 => course) public courseDetails;
    // [courseId] => struct course
    mapping(uint256 => partnerCourse) public partnerCourseDetails;
    // [tokenId] => courseId(s)
    mapping(uint256 => uint256[]) public enrolledCourses;
    // [tokenId (Instructor)] => courseId(s)
    mapping(uint256 => uint256[]) public instructorCourses;
    // [paymentId => struct Fee
    mapping(uint256 => fee) public paymentDetails;

    constructor() ERC721("LearnETH", "LETH") {}

    event partnerAdded(uint256 partnerTokenId, uint256 referrerTokenId, uint256 father1, uint256 level, uint256 position, uint256 subscribedTill);
    event studentAdded(uint256 studentTokenId, uint256 referrerTokenId, uint256 father);
    event instructorAdded(uint256 instructorTokenId, uint256 referrerTokenId, uint256 father);
    event courseAdded(uint256 courseId, string courseName, uint256 instructorTokenId);
    event paidForCourse(uint256 paymentId, string orderId, uint256 paidBy, uint256 paidTo, uint256 paidFor, uint256 paidAmount, uint256 paidAt);
    event partnerRenewal(uint256 partnerTokenId, uint256 subscribedTill);
    event refundIssued(uint256 paymentId);
    event balanceWithdraw(uint256 withdrawnBy,uint256 withdrawnAmount);

    // feeType: 0 - studentUplineFee, 1 - studentPersonalReferrerFee, 2 - instructorFee, 3 - instructorUplineFee, 4 - instructorPersonalReferrerFee
    // feeType: 5 - instructorFeePC, 6 - instructorUplineFeePC, 7 - instructorPersonalReferrerFeePC
    // id: paymentId for type 0-4, partnerCourseId for type 5-7
    event feeDistributed(uint256 id, uint256 beneficiaryTokenId, uint256 amount, uint feeType);

    // feeType: 0 - partnerUplineFee, 1 - partnerPersonalReferrerFee
    event partnerFeeDistributed(uint256 partnerTokenId, uint256 beneficiaryTokenId, uint256 months, uint256 amount, uint feeType);

    // READ FUNCTIONS // ------------------------------------------------------------- //

    function totalSupply() public view returns(uint256) {
        uint256 supply = _tokenIdCounter;
        return supply;
    }

    // ADMIN FUNCTIONS // ------------------------------------------------------------- //

    // assigns tokenId "1" and nodeType "5" to contract Owner
    function initiatePartnerNetwork() external onlyOwner {
        require(!initiated,"Already Initited");
        require(msg.sender == owner(), "Only owner can initiate the network");
        _tokenIdCounter+=1;
        uint256 tokenId = _tokenIdCounter;
        _safeMint(msg.sender, tokenId);
        nodeDetails[tokenId].nodeType = 5; //Special Type for parent node
        nodeDetails[tokenId].level = 1;
        nodeDetails[tokenId].position = 1;
        partnerNodeTokenMapping[1][1] = tokenId;
        initiated = true;
        
        emit partnerAdded(tokenId, 0, 0, 1, 1, 0);
        _tokenIdCounter+=5781;
    }

    //assign special status to a partner
    function assignPriviledge(uint256 _tokenId, uint8 _nodeType) external onlyOwner {
        require(msg.sender == owner(), "Only owner can assign special priviledge");
        nodeDetails[_tokenId].nodeType = _nodeType;
    }

    // Contract owner sets TopWallet
    function setTopNodeWallet(address _walletAddress) external onlyOwner {
        topNodeWallet = _walletAddress;
    }

    function updatePartnerCourse(uint256 _partnerCourseId, string memory _courseName, uint256 _instructorTokenId) external onlyOwner {
        partnerCourseDetails[_partnerCourseId].courseName = _courseName;
        partnerCourseDetails[_partnerCourseId].instructorTokenId = _instructorTokenId;
    }

    function setCurrentPartnerCourseId(uint256 _partnerCourseId) external onlyOwner {
        currentPartnerCourseId = _partnerCourseId;
    }

    // This method allows Contract Owner to withdraw balance to topWallet
    function withdrawTopWallet() external onlyOwner{
        uint256 bal = nodeDetails[1].balance;
        require(bal > 0,"No balance to withdraw");
        nodeDetails[1].balance = 0;
        (bool sent, ) = topNodeWallet.call{value: bal}("");
        require(sent, "Failed to send Ether");
    }

    // To be scheduled for 1st of each month
    function updateCurrentPartnerCourseId() external onlyOwner {
        partnerCourseDetails[currentPartnerCourseId].claimable = true; 
        currentPartnerCourseId += 1;
    }

    // PUBLIC FUNCTIONS // ------------------------------------------------------------- //

    // REGISTER PARTNER // ------------------------------------------------------------- //

    function registerAsPartner(uint256 _referrerTokenId, uint256 _months) public payable {
        require(_exists(_referrerTokenId),"Referrer token Id is invalid");
        //require(msg.value == partnerFee,"Incorrect value");

        uint256 currentFather;
        uint256 _personalReferrer;

        if(nodeDetails[_referrerTokenId].nodeType >= 2) {
            currentFather = _referrerTokenId;
            _personalReferrer = _referrerTokenId;
        }
        else {
            currentFather = nodeDetails[_referrerTokenId].father1;
            _personalReferrer = nodeDetails[_referrerTokenId].father1;
        }

        _tokenIdCounter+=1;
        uint256 tokenId = _tokenIdCounter;
        _safeMint(msg.sender, tokenId);
        (uint256 _level, uint256 _position) = getNextNode(currentFather);
        uint256 f_position;

        if(_position.mod(3) == 0) {
            f_position = _position.div(3);
        }
        else {
            f_position = _position.div(3) + 1;
        }
        uint256 _father1 = partnerNodeTokenMapping[_level - 1][f_position];   
        nodeDetails[tokenId].nodeType = 2;
        nodeDetails[tokenId].level = _level;
        nodeDetails[tokenId].position = _position;
        nodeDetails[tokenId].personalReferrer = _personalReferrer;
        nodeDetails[tokenId].father1 = _father1;
        uint256 _duration = _months.mul(monthDuration);
        nodeDetails[tokenId].subscribedTill = block.timestamp.add(_duration);
        partnerNodeTokenMapping[_level][_position] = tokenId;
        nodeDetails[_personalReferrer].totalRecruits+=1;

        emit partnerAdded(tokenId, _personalReferrer, _father1, _level, _position, block.timestamp.add(_duration));
        distributePartnerCourseFee(tokenId, _months, msg.value);           
           
    }

    function upgradeInstructorAsPartner(uint256 _instructorTokenId, uint256 _months) public payable {
        require(msg.sender == ownerOf(_instructorTokenId), "Not the owner of tokenId");
        require(nodeDetails[_instructorTokenId].nodeType == 1, "Not an instructor");

        uint256 currentFather = nodeDetails[_instructorTokenId].father1;

        _tokenIdCounter+=1;
        uint256 tokenId = _tokenIdCounter;
        _safeMint(msg.sender, tokenId);
        (uint256 _level, uint256 _position) = getNextNode(currentFather);
        uint256 f_position;

        if(_position.mod(3) == 0) {
            f_position = _position.div(3);
        }
        else {
            f_position = _position.div(3) + 1;
        }
        uint256 _father1 = partnerNodeTokenMapping[_level - 1][f_position];   
        nodeDetails[tokenId].nodeType = 2;
        nodeDetails[tokenId].level = _level;
        nodeDetails[tokenId].position = _position;
        nodeDetails[tokenId].personalReferrer = currentFather;
        nodeDetails[tokenId].father1 = _father1;
        uint256 _duration = _months.mul(monthDuration);
        nodeDetails[tokenId].subscribedTill = block.timestamp.add(_duration);
        partnerNodeTokenMapping[_level][_position] = tokenId;
        nodeDetails[currentFather].totalRecruits+=1;

        emit partnerAdded(tokenId, currentFather, _father1, _level, _position, block.timestamp.add(_duration));   
        distributePartnerCourseFee(tokenId, _months, msg.value);  

    }

    function upgradeStudentAsPartner(uint256 _tokenId, uint256 _months) public payable {
        require(_exists(_tokenId) && nodeDetails[_tokenId].nodeType == 0, "Not a valid student token Id");
        //require(msg.value == partnerFee,"Incorrect value");
       
        uint256 currentReferrerTokenId = nodeDetails[_tokenId].personalReferrer;
        uint256 currentFather = nodeDetails[_tokenId].father1;

        (uint256 _level, uint256 _position) = getNextNode(currentFather);
        nodeDetails[_tokenId].nodeType = 2;
        nodeDetails[_tokenId].level = _level;
        nodeDetails[_tokenId].position = _position;
        
        uint256 f_position;
        if(_position.mod(3) == 0) {
            f_position = _position.div(3);
        }
        else {
            f_position = _position.div(3) + 1;
        }
        uint256 _father1 = partnerNodeTokenMapping[_level - 1][f_position];
        nodeDetails[_tokenId].father1 = _father1;
        nodeDetails[_tokenId].personalReferrer = currentFather;
        uint256 _duration = _months.mul(monthDuration);
        nodeDetails[_tokenId].subscribedTill = block.timestamp.add(_duration);
        partnerNodeTokenMapping[_level][_position] = _tokenId;
        nodeDetails[currentFather].totalRecruits+=1;
        
        emit partnerAdded(_tokenId, currentReferrerTokenId, _father1, _level, _position, block.timestamp.add(_duration));    
        distributePartnerCourseFee(_tokenId, _months, msg.value);    
    }

    // PARTNER FUNCTIONS // ------------------------------------------------------------- //

    function enrolForPartnerCourse(uint256 _tokenId, uint256 _months) public payable {
        require(msg.sender == ownerOf(_tokenId), "Not the owner of tokenId");
        require(nodeDetails[_tokenId].nodeType == 2 || nodeDetails[_tokenId].nodeType == 4,"Not a partner");
        uint256 _amount = msg.value;
        uint256 _duration = _months.mul(monthDuration);
        nodeDetails[_tokenId].subscribedTill = nodeDetails[_tokenId].subscribedTill.add(_duration);
        emit partnerRenewal(_tokenId, nodeDetails[_tokenId].subscribedTill.add(_duration));
        distributePartnerCourseFee(_tokenId, _months, _amount);
    }

    // REGISTER STUDENT // ------------------------------------------------------------- //

    function registerStudent(uint256 _referrerTokenId) public {
        require(_exists(_referrerTokenId), "Not a valid referrer Id");
        _tokenIdCounter+=1;
        uint256 tokenId = _tokenIdCounter;
        _safeMint(msg.sender, tokenId);
        uint256 f_tokenId  = _referrerTokenId;
        nodeDetails[tokenId].nodeType = 0;
        nodeDetails[tokenId].personalReferrer = _referrerTokenId;
        if(nodeDetails[_referrerTokenId].nodeType >= 2) {
            f_tokenId = _referrerTokenId;
        }
        else {
            while(nodeDetails[f_tokenId].nodeType < 2) {
                f_tokenId = nodeDetails[f_tokenId].father1;
            }
        }
        nodeDetails[tokenId].father1 = f_tokenId;
        
        emit studentAdded(tokenId, _referrerTokenId, f_tokenId);
    }

    function upgradeInstructorAsStudent(uint256 _instructorTokenId) public {
        require(msg.sender == ownerOf(_instructorTokenId), "Not the owner of tokenId");
        require(nodeDetails[_instructorTokenId].nodeType == 1, "Not an instructor");

        uint256 _personalReferrer = nodeDetails[_instructorTokenId].personalReferrer;
        uint256 _father1 = nodeDetails[_instructorTokenId].father1;

        _tokenIdCounter+=1;
        uint256 _studentTokenId = _tokenIdCounter;
        _safeMint(msg.sender, _studentTokenId);

        nodeDetails[_studentTokenId].nodeType = 0;
        nodeDetails[_studentTokenId].personalReferrer = _personalReferrer;
        nodeDetails[_studentTokenId].father1 = _father1;

        emit studentAdded(_studentTokenId, _personalReferrer, _father1);
    }

    // STUDENT FUNCTIONS // ------------------------------------------------------------- //

    function enrolForCourse(uint256 _tokenId, uint256[] memory _courseId, string memory _orderId) public payable {
        require(msg.sender == ownerOf(_tokenId), "Not the owner of tokenId");
        //require(msg.value == courseDetails[_courseId].courseFee, "Incorrect fee");
        for(uint i=0; i<_courseId.length;i++) {
            require(_courseId[i] < courseIndex, "Incorrect Course Id");
        
            enrolledCourses[_tokenId].push() = _courseId[i];
            nodeDetails[nodeDetails[_tokenId].personalReferrer].lastSaleAt = block.timestamp;
            paymentDetails[paymentIndex].paidBy = _tokenId;
            paymentDetails[paymentIndex].paidTo = courseDetails[_courseId[i]].instructorTokenId;
            paymentDetails[paymentIndex].paidFor = _courseId[i];
            paymentDetails[paymentIndex].paidAmount = msg.value;
            paymentDetails[paymentIndex].paidAt = block.timestamp;
            paymentDetails[paymentIndex].status = 0;

            emit paidForCourse(paymentIndex, _orderId, _tokenId, courseDetails[_courseId[i]].instructorTokenId, _courseId[i], msg.value, block.timestamp);
            paymentIndex+=1;
        }
    }

    function getRefund(uint256 _tokenId, uint256 _paymentId) public {
        require(msg.sender == ownerOf(_tokenId), "Invalid call");
        require(_tokenId == paymentDetails[_paymentId].paidBy, "Course not paid by the caller");
        require(paymentDetails[_paymentId].status == 0,"Already distributed or refunded");
        require(block.timestamp.sub(monthDuration) < paymentDetails[_paymentId].paidAt, "Refund eligibility duration lapsed");

        paymentDetails[_paymentId].status = 2;
        nodeDetails[_tokenId].balance = nodeDetails[_tokenId].balance.add(paymentDetails[_paymentId].paidAmount);
        emit refundIssued(_paymentId);

    } 

    // REGISTER INSTRUCTOR // ------------------------------------------------------------- //
   
    // An 'instructor' can be referred by an existing 'partner' or 'student' or 'instructor'
    // HOWEVER a 'student'/'instructor' referring an 'instructor' would not be entitled to any benefits
    // Both 'personalReferrer' and 'father1' of an instructor would be a 'partner'.

    function registerInstructor(uint256 _referrerTokenId) public {
        require(_exists(_referrerTokenId), "Not a valid referrer Id");
        _tokenIdCounter+=1;
        uint256 tokenId = _tokenIdCounter;
        _safeMint(msg.sender, tokenId);
        uint256 _node = _referrerTokenId;
        if(nodeDetails[_node].nodeType >= 2) {

            nodeDetails[tokenId].nodeType = 1;
            nodeDetails[tokenId].personalReferrer = _node;
            nodeDetails[tokenId].father1 = _node;
        }
        else {
            while(nodeDetails[_node].father1 < 2) {
                _node = nodeDetails[_node].father1;
            }

            nodeDetails[tokenId].nodeType = 1;
            nodeDetails[tokenId].personalReferrer = nodeDetails[_node].father1;
            nodeDetails[tokenId].father1 = nodeDetails[_node].father1;
        }
        
        emit instructorAdded(tokenId, _referrerTokenId, nodeDetails[tokenId].father1); 
    }

    function upgradeStudentAsInstructor(uint256 _studentTokenId) public {
        require(msg.sender == ownerOf(_studentTokenId), "Not the owner of tokenId");
        require(nodeDetails[_studentTokenId].nodeType == 0, "Not a student");

        uint256 _father1 = nodeDetails[_studentTokenId].father1;

        _tokenIdCounter+=1;
        uint256 _instructorTokenId = _tokenIdCounter;
        _safeMint(msg.sender, _instructorTokenId);

        nodeDetails[_instructorTokenId].nodeType = 1;
        nodeDetails[_instructorTokenId].personalReferrer = _father1;
        nodeDetails[_instructorTokenId].father1 = _father1;

        emit instructorAdded(_instructorTokenId, _father1, _father1);

    }

    function upgradePartnerAsInstructor(uint256 _partnerTokenId) public {
        require(msg.sender == ownerOf(_partnerTokenId), "Not the owner of tokenId");
        require(nodeDetails[_partnerTokenId].nodeType >= 2, "Not a partner");

        uint256 _personalReferrer = nodeDetails[_partnerTokenId].personalReferrer;
        uint256 _father1 = nodeDetails[_partnerTokenId].father1;

        _tokenIdCounter+=1;
        uint256 _instructorTokenId = _tokenIdCounter;
        _safeMint(msg.sender, _instructorTokenId);

        nodeDetails[_instructorTokenId].nodeType = 1;
        nodeDetails[_instructorTokenId].personalReferrer = _personalReferrer;
        nodeDetails[_instructorTokenId].father1 = _father1;

        emit instructorAdded(_instructorTokenId, _personalReferrer, _father1);
    }

    // INSTRUCTOR FUNCTIONS // ------------------------------------------------------------- //

    function addCourse(uint256 _tokenId, string memory _courseName, uint256 _courseFee) public {
        require(msg.sender == ownerOf(_tokenId), "Not the owner of tokenId");
        require(nodeDetails[_tokenId].nodeType == 1, "Only an instructor can add a course");
        courseDetails[courseIndex].courseName = _courseName;
        courseDetails[courseIndex].courseFee = _courseFee;
        courseDetails[courseIndex].instructorTokenId = _tokenId;
        instructorCourses[_tokenId].push() = courseIndex;
		emit courseAdded(courseIndex, _courseName, _tokenId);
        courseIndex+=1;
       
    }

    function unlockPayment(uint256 _paymentId) external {
        require(msg.sender == ownerOf(1) || msg.sender == ownerOf(paymentDetails[_paymentId].paidTo), "Not authorized");
        require(paymentDetails[_paymentId].status == 0,"Already distributed or refunded");
        require(paymentDetails[_paymentId].paidAmount > 0, "Free course not eligible for distribution");
        require(paymentDetails[_paymentId].paidAt.add(monthDuration) < block.timestamp,"Still in refund eligibility window");

        uint256 studentTokenId = paymentDetails[_paymentId].paidBy;
        uint256 instructorTokenId = paymentDetails[_paymentId].paidTo;
        uint256 totalFee = paymentDetails[_paymentId].paidAmount;
        uint256 studentReferrerFee = totalFee.mul(105).div(1200);
        uint256 instructorReferrerFee = totalFee.mul(45).div(1200);
        uint256 studentUplineFee = totalFee.mul(315).div(1200);
        uint256 instructorUplineFee = totalFee.mul(135).div(1200);

        nodeDetails[instructorTokenId].balance+=totalFee.div(2);
        emit feeDistributed(_paymentId, instructorTokenId, totalFee.div(2), 2);
        // Does this require eligibility check?
        nodeDetails[nodeDetails[studentTokenId].personalReferrer].balance+=studentReferrerFee;
        emit feeDistributed(_paymentId, nodeDetails[studentTokenId].personalReferrer, studentReferrerFee, 1);
        // Does this require eligibility check?
        nodeDetails[nodeDetails[instructorTokenId].personalReferrer].balance+=instructorReferrerFee;
        emit feeDistributed(_paymentId, nodeDetails[instructorTokenId].personalReferrer, instructorReferrerFee, 4);
        distributeUplineFee(_paymentId, studentTokenId, studentUplineFee, 0);
        distributeUplineFee(_paymentId, instructorTokenId, instructorUplineFee, 3);

        paymentDetails[_paymentId].status = 1;
    }

    function distributePartnerCourseBalance(uint256 _tokenId, uint256 _partnerCourseId) external {
        require(msg.sender == ownerOf(_tokenId), "Not authorized");
        require(_tokenId == partnerCourseDetails[_partnerCourseId].instructorTokenId,"Not the instructor of this course");
        require(partnerCourseDetails[_partnerCourseId].claimable, "Not claimable");

        nodeDetails[_tokenId].balance += partnerCourseDetails[_partnerCourseId].balance.mul(75).div(100);
        emit feeDistributed(_partnerCourseId, _tokenId, partnerCourseDetails[_partnerCourseId].balance.mul(75).div(100), 5);
        nodeDetails[nodeDetails[_tokenId].personalReferrer].balance += partnerCourseDetails[_partnerCourseId].balance.mul(75).div(1200);
        emit feeDistributed(_partnerCourseId, nodeDetails[_tokenId].personalReferrer, partnerCourseDetails[_partnerCourseId].balance.mul(75).div(1200), 7);
        distributeUplineFee(_partnerCourseId, _tokenId, partnerCourseDetails[_partnerCourseId].balance.mul(225).div(1200), 6);
        partnerCourseDetails[_partnerCourseId].balance = 0;
    }

    // GENERIC FUNCTIONS // ------------------------------------------------------------- //

    // This method allows users Partners/Students/Instructors (except TokenId 1) to withdraw their balance
    function withdrawBalance(uint256 _tokenId) public {
        require(msg.sender == ownerOf(_tokenId) && _tokenId != 1, "Not Authorized");
        uint256 bal = nodeDetails[_tokenId].balance;
        require(bal > 0,"No balance to withdraw");
        nodeDetails[_tokenId].balance = 0;

        (bool success, ) = msg.sender.call{value: bal}("");
        require(success, "Withdrawal failed.");
		emit balanceWithdraw(_tokenId, bal);
    }

    // HELPER FUNCTIONS // ------------------------------------------------------------- //

    function getNextNode(uint256 _tokenId) public view returns(uint256 _level, uint256 _position) {
        require(_exists(_tokenId) && nodeDetails[_tokenId].nodeType >=2, "Not a partner");
        uint256 level = nodeDetails[_tokenId].level;
        uint256 currentPosition = nodeDetails[_tokenId].position;
        uint256 positionLeft = currentPosition;
        uint256 positionRight = currentPosition;
        uint256 position;
        uint256 id = 1;

        while(id != 0) {  

            level = level + 1;
            positionLeft = positionLeft.mul(3).sub(2);
            positionRight = positionRight.mul(3);

            for(position = positionLeft; position<= positionRight; position++) {
                id = partnerNodeTokenMapping[level][position];
                if (id == 0) {
                    break;
                }                
            }            
        }

        return(level,position);
    }

    function estimateFeeDistribution(uint256 _paymentId) public view returns(earnings[] memory studentUpline, earnings[] memory instructorUpline) {
        uint256 studentTokenId = paymentDetails[_paymentId].paidBy;
        uint256 instructorTokenId = paymentDetails[_paymentId].paidTo;
        uint256 totalFee = paymentDetails[_paymentId].paidAmount;
        uint256 studentReferrerFee = totalFee.mul(105).div(1200);
        uint256 instructorReferrerFee = totalFee.mul(45).div(1200);
        uint256 studentUplineFee = totalFee.mul(315).div(1200);
        uint256 instructorUplineFee = totalFee.mul(135).div(1200);

        earnings[] memory _studentUpline = new earnings[](10);
        earnings[] memory _instructorUpline = new earnings[](11);

        //earnings[9] memory _studentUpline;
        // assign 0th index to student's personal Referrer followed by student upline
        _studentUpline[0] = earnings(nodeDetails[studentTokenId].personalReferrer, studentReferrerFee);

        uint256 _father1 = nodeDetails[studentTokenId].father1;
        for(uint i=1; i<=9; i++) {
            if(_father1 == 1) {break;}
            else {
                _studentUpline[i] = earnings(_father1, studentUplineFee.div(9));
            }  
            _father1 = nodeDetails[_father1].father1;      
        }

        // assign 0th index to Instructor
        // assign 1st index to instructor's personal Referrer followed by Instructor upline
        _instructorUpline[0] = earnings(instructorTokenId,totalFee.div(2));
        _instructorUpline[1] = earnings(nodeDetails[instructorTokenId].personalReferrer, instructorReferrerFee);

        _father1 = nodeDetails[instructorTokenId].father1;
        for(uint i=2; i<=10; i++) {
            if(_father1 == 1) {break;}
            else {
                _instructorUpline[i] = earnings(_father1, instructorUplineFee.div(9));
            }  
            _father1 = nodeDetails[_father1].father1;      
        } 

        return(_studentUpline, _instructorUpline);
    } 

    function isEligibleForDistribution(uint256 _tokenId, uint _depth) internal view returns(bool) {
        uint256 nodeType = nodeDetails[_tokenId].nodeType;
        if(nodeType == 0 || nodeType == 1 ) { return false;} //unlikely scenario
        else if(nodeType == 3) {return true;} //exempted from partner requirements
        else if(nodeType == 4) {
            uint256 subscribedTill = nodeDetails[_tokenId].subscribedTill;
            if(subscribedTill < block.timestamp) {return false;}
            else return true;
        }
        else {

            uint256 subscribedTill = nodeDetails[_tokenId].subscribedTill;
            uint256 totalRecruits = nodeDetails[_tokenId].totalRecruits;
            uint256 lastSaleAt = nodeDetails[_tokenId].lastSaleAt;

            if(subscribedTill < block.timestamp || lastSaleAt < block.timestamp.sub(monthDuration)) {return false;}
            else if(totalRecruits == 0 || totalRecruits <= 2 && _depth > 3 || totalRecruits <=4 && _depth > 6) {return false;}
            else return true;

        }
    }  

    function distributePartnerCourseFee(uint256 _tokenId, uint256 _months, uint256 _amount) internal {
        require(_months > 0 && _months <=12, "Invalid months count");
        //require(_amount == _months.mul(partnerCourseFee), "Incorrect fee");
        uint256 instructorSharePerMonth = (_amount).mul(30).div(100).div(_months);
        uint256 partnerShare = (_amount).mul(70).div(100);

        for(uint i=0; i< _months; i++) {
            partnerCourseDetails[currentPartnerCourseId.add(i)].balance+=instructorSharePerMonth;
        }
        
        uint256 twelth = partnerShare.div(12);
        nodeDetails[nodeDetails[_tokenId].personalReferrer].balance+=twelth.mul(3);
        emit partnerFeeDistributed(_tokenId, nodeDetails[_tokenId].personalReferrer, _months, twelth.mul(3), 1);

        distributePCUplineFee(_tokenId, twelth.mul(9), _months);
    }

    function distributeUplineFee(uint256 _paymentId, uint256 _tokenId, uint256 _amount, uint _type) internal {
        uint256 _father1 = nodeDetails[_tokenId].father1;
        uint256 _share = _amount.div(9);
        for(uint i=1; i<=9; i++) {
            if(_father1 == 1) {break;}
            else {
                if(isEligibleForDistribution(_father1,i)) {
                    nodeDetails[_father1].balance+=_share;
                    emit feeDistributed(_paymentId, _father1, _share, _type);
                    _amount-=_share;
                }
                else {
                    emit feeDistributed(_paymentId, _father1, 0, _type);  
                }
            }  
            _father1 = nodeDetails[_father1].father1;      
        }        
        nodeDetails[1].balance += _amount;
    }

    function distributePCUplineFee(uint256 _tokenId, uint256 _amount, uint _months) internal {
        uint256 _father1 = nodeDetails[_tokenId].father1;
        uint256 _share = _amount.div(9);
        for(uint i=1; i<=9; i++) {
            if(_father1 == 1) {break;}
            else {
                if(isEligibleForDistribution(_father1,i)) {
                    nodeDetails[_father1].balance+=_share;
                    emit partnerFeeDistributed(_tokenId, _father1, _months, _share, 0);
                    _amount-=_share;
                }
                else {
                    emit partnerFeeDistributed(_tokenId, _father1, _months, 0, 0);  
                }
            }  
            _father1 = nodeDetails[_father1].father1;      
        }        
        nodeDetails[1].balance += _amount;
    }

    // FUNCTIONS OVERRIDES // ------------------------------------------------------------- //

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        string memory memberType; 
        
        if(nodeDetails[tokenId].nodeType == 0) {
            memberType = "Student";
        }
        else if(nodeDetails[tokenId].nodeType == 1) {
            memberType = "Instructor";
        }
        else memberType = "Partner";

        string memory json = Base64.encode(
            bytes(
                string(
                    abi.encodePacked('{"name": "LearnETH #', Strings.toString(tokenId), '", "description": "LearnETH is a Self-governed global eLearning marketplace, where people can teach or gain skills and knowledge for a fee or for free.", "image": "ipfs://bafybeig7mbjsf2yd6q44xigohksdmokmu7jqf3c2m5d6i4ajtfluqeevee/learnETH.png" , "attributes": [{"trait_type": "Member Type", "value": "',memberType,'"}]}'
                    )
                )
            )
        );

        string memory output = string(
            abi.encodePacked("data:application/json;base64,", json)
        );
        return output;
    }
    
}
