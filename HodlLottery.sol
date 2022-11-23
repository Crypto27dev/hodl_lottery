//SPDX-License-Identifier: MIT
pragma solidity 0.8.7;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
// import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./ReentrancyGuard.sol";
import "./HodlNFT.sol";

contract HodlLottery is Ownable, ReentrancyGuard {
    // 2 kinds of lottery
    enum LOTTERY_TYPE {
        LOTTERY_WEEKLY,
        LOTTERY_BI_DAILY
    }

    // lottery status
    enum LOTTERY_STATUS {
        LOTTERY_START,
        LOTTERY_CLOSED,
        LOTTERY_PICKED
    }

    // team funds wallet address
    address payable _teamFundsWallet       = payable(0xbAB8E9cA493E21d5A3f3e84877Ba514c405be0e1);

    // private seed data for claculating picked number
    uint256 private constant    MAX_UINT_VALUE = (2**255 - 1 + 2**255);
    uint256 private             pri_seedValue;
    string private              pri_seedString;
    address private             pri_seedAddress;

    // distribution percentage of funds
    uint256 constant REWARD_FOR_TEAM_FUND           = 1;                        // 10% goes to team funds
    uint256 constant REWARD_FOR_REWARD_POOL         = 9;                        // 90% goes to rewards pool
    uint256 constant LOTTERY_FEE                    = 1;                        // 10% goes to team funds

    // price of ticket
    uint256 PRICE_TICKET_WEEKLY                     = 1 * 10 ** 17;             // 0.1 AVAX
    uint256 PRICE_TICKET_BI_DAILY                   = 3 * 10 ** 16;             // 0.03 AVAX

    // lottery loop time
    uint256 WEEKLY_LOOP_TIME                        = 60 * 60 * 24 * 7;         // 7 days
    uint256 BI_DAILY_LOOP_TIME                      = 60 * 60 * 24 * 2;         // 2 days

    // this is for first lottery
    uint256 constant TEMPORARY_TIME                 = 60 * 60 * 5;                  // 5 hour

    // when user buy ticket, NFT is minted
    HodlNFT public nftContract;

    // this is for get user ticket numbers
    struct Ticket_Address {
        uint256 timestamp;
        uint16 startNumber;
        uint16 count;
    }

    // return ticket status
    struct Ret_Ticket_Status {
        LOTTERY_STATUS status;
        uint256 totalCount;
        uint256 poolAmount;
    }

    // there are 2 kinds of lottery
    // weekly lottery: per week
    // bi-daily lottery: per bi-daily
    struct Lottery_Info {
        uint256 lotteryID;                                              // lottery id
        LOTTERY_STATUS lotteryStatus;                                   // current status of lottery
        uint256 lotteryTimeStamp;                                       // lottery time stamp
        uint256 poolAmount;                                             // all amount of inputed AVAX
        uint16[] ids;                                                   // start ids of tickes user bought
        uint16 winnerID;
        uint256 winnerPrize;
        mapping(uint16 => address) members;                             // address of start id
        mapping(uint16 => uint16) ticketsOfMember;                      // ticket ids of members
    }

    // lottery infos of weekly lottery
    mapping(uint256 => Lottery_Info) internal allWeeklyLotteryInfos;

    // lottery infos of bi-daily lottery
    mapping(uint256 => Lottery_Info) internal allBiDailyLotteryInfos;

    // last available lottery id
    uint256 public weeklyLotteryCounter;
    uint256 public biDailyLotteryCounter;

    // this is sum of total payout
    uint256 public totalMarketcap;

    // invest amount current site was paid
    uint256 private totalInvestments;

    // all events
    event Received (address from, uint amount);
    event Fallback (address from, uint amount);
    event SetTeamFundsAddress (address addr);
    event SetWeeklyTicketPrice (uint256 price);
    event SetBiDailyTicketPrice (uint256 price);
    event ChangeLotteryInfo (LOTTERY_TYPE lottery_type, uint256 lottery_id, LOTTERY_STATUS status, uint256 time);
    event ClearLotteryInfo (LOTTERY_TYPE lottery_type, uint256 lottery_id);
    event CreateNewLotteryInfo (LOTTERY_TYPE lottery_type, uint256 lottery_id, LOTTERY_STATUS status);
    event BuyTicket (address addr, LOTTERY_TYPE lottery_type, uint256 lottery_id, uint256 time, uint16 startNo, uint16 count);
    event LogAllSeedValueChanged (address addr, uint256 seed1, uint256 seed2, string seed3, address seed4);
    event SelectWinner (LOTTERY_TYPE lottery_type, uint256 lottery_id, uint256 time, address addr, uint256 ticketID, uint256 price);
    event GivePriceToWinner(LOTTERY_TYPE lottery_type, uint256 lottery_id, address addr, uint256 time, uint256 ticketID, uint256 amount);
    event SetWeeklyLoopTime (uint256 loopTime);
    event SetBiDailyLoopTime (uint256 loopTime);
    event SetTotalInvestment (uint256 loopTime);
    event SetLotteryStatus (LOTTERY_TYPE lottery_type, uint256 lottery_id);
    event WithdrawAll (address addr, uint256 balance);

    // contructor
    constructor (
        uint256 _seedValue,
        string memory _seedString,
        address _seedAddress,
        address _nftContract
     )
    {
        pri_seedValue = _seedValue;
        pri_seedString = _seedString;
        pri_seedAddress = _seedAddress;

        weeklyLotteryCounter = 0;
        biDailyLotteryCounter = 0;

        nftContract = HodlNFT(_nftContract);
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    fallback() external payable { 
        emit Fallback(msg.sender, msg.value);
    }

    function setTeamFundsAddress (address _addr) external onlyOwner {
        _teamFundsWallet = payable(_addr);
        emit SetTeamFundsAddress (_teamFundsWallet);
    }

    function getTeamFundsAddress () external view returns (address) {
        return _teamFundsWallet;
    }

    function setWeeklyTicketPrice (uint256 _ticketPrice) external onlyOwner {
        PRICE_TICKET_WEEKLY = _ticketPrice;
        emit SetWeeklyTicketPrice (_ticketPrice);
    }

    function getWeeklyTicketPrice () external view returns (uint256) {
        return PRICE_TICKET_WEEKLY;
    }

    function setBiDailyTicketPrice (uint256 _ticketPrice) external onlyOwner {
        PRICE_TICKET_BI_DAILY = _ticketPrice;
        emit SetBiDailyTicketPrice (_ticketPrice);
    }

    function getBiDailyTicketPrice () external view returns (uint256) {
        return PRICE_TICKET_BI_DAILY;
    }

    function setWeeklyLoopTime (uint256 _time) external onlyOwner {
        WEEKLY_LOOP_TIME = _time;
        emit SetWeeklyLoopTime (WEEKLY_LOOP_TIME);
    }

    function getWeeklyLoopTime () external view returns (uint256) {
        return WEEKLY_LOOP_TIME;
    }

    function setBiDailyLoopTime (uint256 _time) external onlyOwner {
        BI_DAILY_LOOP_TIME = _time;
        emit SetBiDailyLoopTime (BI_DAILY_LOOP_TIME);
    }

    function getBiDailyLoopTime () external view returns (uint256) {
        return BI_DAILY_LOOP_TIME;
    }

    function setTotalInvestment (uint256 _value) external onlyOwner {
        totalInvestments = _value;
        emit SetTotalInvestment (totalInvestments);
    }

    function getTotalInvestment () external view returns (uint256) {
        return totalInvestments;
    }

    function withdrawAll() external onlyOwner{
        uint256 balance = address(this).balance;
        address payable mine = payable(msg.sender);
        if(balance > 0) {
            mine.transfer(balance);
        }
        emit WithdrawAll(msg.sender, balance);
    }

    // admin can oly change status and timestamp of started lottery
    function changeLotteryInfo (LOTTERY_TYPE _lotteryType, uint256 _lotteryID, LOTTERY_STATUS _status, uint256 _timestamp) external onlyOwner {
        Lottery_Info storage lottoInfo;
        if (_lotteryType == LOTTERY_TYPE.LOTTERY_WEEKLY) {
            require(_lotteryID < weeklyLotteryCounter, "This lotteryID does not exist.");
            lottoInfo = allWeeklyLotteryInfos[_lotteryID];
        }
        else {
            require(_lotteryID < biDailyLotteryCounter, "This lotteryID does not exist.");
            lottoInfo = allBiDailyLotteryInfos[_lotteryID];
        }
        require(lottoInfo.lotteryStatus == LOTTERY_STATUS.LOTTERY_START, "admin can't change data");

        lottoInfo.lotteryStatus = _status;
        lottoInfo.lotteryTimeStamp = _timestamp;

        emit ChangeLotteryInfo (_lotteryType, _lotteryID, _status, _timestamp);
    }

    // admin can remove lottery
    function clearLotteryInfo (LOTTERY_TYPE _lotteryType, uint256 _lotteryID) external onlyOwner {
        if (_lotteryType == LOTTERY_TYPE.LOTTERY_WEEKLY) {
            require(_lotteryID < weeklyLotteryCounter, "This lotteryID does not exist.");
            delete allWeeklyLotteryInfos[_lotteryID];
            weeklyLotteryCounter --;
        }
        else {
            require(_lotteryID < biDailyLotteryCounter, "This lotteryID does not exist.");
            delete allBiDailyLotteryInfos[_lotteryID];
            biDailyLotteryCounter --;
        }

        emit ClearLotteryInfo (_lotteryType, _lotteryID);
    }

    // only owner can create new lottery
    function createNewLotteryInfo (LOTTERY_TYPE lottery_type) external onlyOwner {
        require (lottery_type <= LOTTERY_TYPE.LOTTERY_BI_DAILY, "This lottery doesn't exist");
        Lottery_Info storage newLottery;
        uint256 nLotteryTime = block.timestamp + TEMPORARY_TIME;
        uint256 poolAmount = 0;
        if (lottery_type == LOTTERY_TYPE.LOTTERY_WEEKLY) {
            if (weeklyLotteryCounter > 0) {
                require(allWeeklyLotteryInfos[weeklyLotteryCounter - 1].lotteryStatus == LOTTERY_STATUS.LOTTERY_PICKED, "Previous lottery doesn't complete.");
                nLotteryTime = allWeeklyLotteryInfos[weeklyLotteryCounter - 1].lotteryTimeStamp + WEEKLY_LOOP_TIME;

                // previous pool amount goes to next lottery
                poolAmount = allWeeklyLotteryInfos[weeklyLotteryCounter - 1].poolAmount;
                allWeeklyLotteryInfos[weeklyLotteryCounter - 1].poolAmount = 0;
            }
            newLottery = allWeeklyLotteryInfos[weeklyLotteryCounter];
            newLottery.lotteryID = weeklyLotteryCounter;
            weeklyLotteryCounter ++;
        }
        else {
            if (biDailyLotteryCounter > 0) {
                require(allBiDailyLotteryInfos[biDailyLotteryCounter - 1].lotteryStatus == LOTTERY_STATUS.LOTTERY_PICKED, "Previous lottery doesn't complete.");
                nLotteryTime = allBiDailyLotteryInfos[biDailyLotteryCounter - 1].lotteryTimeStamp + BI_DAILY_LOOP_TIME;
                
                // previous pool amount goes to next lottery
                poolAmount = allBiDailyLotteryInfos[biDailyLotteryCounter - 1].poolAmount;
                allBiDailyLotteryInfos[biDailyLotteryCounter - 1].poolAmount = 0;
            }
            newLottery = allBiDailyLotteryInfos[biDailyLotteryCounter];
            newLottery.lotteryID = biDailyLotteryCounter;
            biDailyLotteryCounter ++;
        }
        newLottery.lotteryStatus = LOTTERY_STATUS.LOTTERY_START;
        newLottery.lotteryTimeStamp = nLotteryTime;
        newLottery.poolAmount = poolAmount;
        newLottery.ids.push(1);
        newLottery.members[1] = address(msg.sender);
        newLottery.ticketsOfMember[1] = 0;

        emit CreateNewLotteryInfo (lottery_type, newLottery.lotteryID, LOTTERY_STATUS.LOTTERY_START);
    }

    // Get remain time of last lottery
    function getLotteryRemainTime(LOTTERY_TYPE _lotteryType, uint256 _lotteryID) external view returns(uint256) {
        if (_lotteryType == LOTTERY_TYPE.LOTTERY_WEEKLY) {
            require(_lotteryID < weeklyLotteryCounter, "This lotteryID does not exist.");
            if (allWeeklyLotteryInfos[_lotteryID].lotteryTimeStamp <= block.timestamp) {
                return 0;
            }
            return allWeeklyLotteryInfos[_lotteryID].lotteryTimeStamp - block.timestamp;
        }
        else {
            require(_lotteryID < biDailyLotteryCounter, "This lotteryID does not exist.");
            if (allBiDailyLotteryInfos[_lotteryID].lotteryTimeStamp <= block.timestamp) {
                return 0;
            }
            return allBiDailyLotteryInfos[_lotteryID].lotteryTimeStamp - block.timestamp;
        }
    }

    // set lottery status after lottery time
    function setLotteryStatus(LOTTERY_TYPE _lotteryType, uint256 _lotteryID) external onlyOwner returns(bool) {
        if (_lotteryType == LOTTERY_TYPE.LOTTERY_WEEKLY) {
            require(_lotteryID < weeklyLotteryCounter, "This lotteryID does not exist.");
            require(allWeeklyLotteryInfos[_lotteryID].lotteryStatus == LOTTERY_STATUS.LOTTERY_START, "This Lottery Status is not Start.");
            require(allWeeklyLotteryInfos[_lotteryID].ids.length > 1, "User has to buy Ticket");
            if (allWeeklyLotteryInfos[weeklyLotteryCounter - 1].lotteryTimeStamp <= block.timestamp) {
                allWeeklyLotteryInfos[_lotteryID].lotteryStatus = LOTTERY_STATUS.LOTTERY_CLOSED;
                allWeeklyLotteryInfos[_lotteryID].lotteryTimeStamp = block.timestamp;
            }
        }
        else {
            require(_lotteryID < biDailyLotteryCounter, "This lotteryID does not exist.");
            require(allBiDailyLotteryInfos[_lotteryID].lotteryStatus == LOTTERY_STATUS.LOTTERY_START, "This Lottery Status is not Start.");
            require(allBiDailyLotteryInfos[_lotteryID].ids.length > 1, "User has to buy Ticket");
            if (allBiDailyLotteryInfos[biDailyLotteryCounter - 1].lotteryTimeStamp <= block.timestamp) {
                allBiDailyLotteryInfos[_lotteryID].lotteryStatus = LOTTERY_STATUS.LOTTERY_CLOSED;
                allBiDailyLotteryInfos[_lotteryID].lotteryTimeStamp = block.timestamp;
            }
        }

        emit SetLotteryStatus (_lotteryType, _lotteryID);
        return true;
    }

    // get full information of _lotteryID
    function getLottoryInfo(LOTTERY_TYPE _lotteryType, uint256 _lotteryID) external view returns(
        uint256,    // startingTimestamp
        uint16,     // winnerID
        address,    // winnerAddress
        uint256,    // PoolAmountInAVAX
        uint16,     // NumberOfLottoMembers
        uint256     // winnerPrize
    )
    {
        Lottery_Info storage lottoInfo;
        if (_lotteryType == LOTTERY_TYPE.LOTTERY_WEEKLY) {
            require(_lotteryID < weeklyLotteryCounter, "This lotteryID does not exist.");
            lottoInfo = allWeeklyLotteryInfos[_lotteryID];
        }
        else {
            require(_lotteryID < biDailyLotteryCounter, "This lotteryID does not exist.");
            lottoInfo = allBiDailyLotteryInfos[_lotteryID];
        }
        uint256 lotteryTimeStamp = lottoInfo.lotteryTimeStamp;
        uint16 winnerID = lottoInfo.winnerID;
        address winnerAddress = lottoInfo.members[lottoInfo.winnerID];
        uint256 poolAmount = lottoInfo.poolAmount;
        uint16 NumberOfLottoMembers = uint16(lottoInfo.ids.length - 1);
        uint256 winnerPrize = lottoInfo.winnerPrize;
        return (
            lotteryTimeStamp,
            winnerID,
            winnerAddress,
            poolAmount,
            NumberOfLottoMembers,
            winnerPrize
        );
    }

    function buyTicket(LOTTERY_TYPE _lotteryType, uint256 _lotteryID, uint16 _numberOfTickets) external payable {
        uint256 payAmount;
        Lottery_Info storage lottoInfo;
        require(_numberOfTickets > 0, "User has to input ticket number.");
        if (_lotteryType == LOTTERY_TYPE.LOTTERY_WEEKLY) {
            require(_lotteryID < weeklyLotteryCounter, "This lotteryID does not exist.");
            lottoInfo = allWeeklyLotteryInfos[_lotteryID];
            payAmount = PRICE_TICKET_WEEKLY * _numberOfTickets;
        }
        else {
            require(_lotteryID < biDailyLotteryCounter, "This lotteryID does not exist.");
            lottoInfo = allBiDailyLotteryInfos[_lotteryID];
            payAmount = PRICE_TICKET_BI_DAILY * _numberOfTickets;
        }
        require(lottoInfo.lotteryTimeStamp >= block.timestamp, "Time is up");
        require(lottoInfo.lotteryStatus == LOTTERY_STATUS.LOTTERY_START, "Lottery doesn't start.");

        // pay AVAX for ticket
        require(msg.value == payAmount, "no enough balance");
        _teamFundsWallet.transfer(payAmount * REWARD_FOR_TEAM_FUND / 10);
        payable(address(this)).transfer(payAmount * REWARD_FOR_REWARD_POOL / 10);
        lottoInfo.poolAmount += payAmount * REWARD_FOR_REWARD_POOL / 10;
        
        // insert data into lottery info
        uint16 numTickets = _numberOfTickets;
        for (uint i = 0; i < numTickets; i ++) {
            nftContract.mintNFT(msg.sender);
        }
        uint16 lastID = lottoInfo.ids[lottoInfo.ids.length - 1];
        uint16 newID = lastID + lottoInfo.ticketsOfMember[lastID];

        // first 10 users can get 2 times chance than others in weekly lottery
        if (_lotteryType == LOTTERY_TYPE.LOTTERY_WEEKLY && lottoInfo.ids.length <= 10) {
            numTickets = _numberOfTickets * 2;
        }
        
        lottoInfo.ids.push(newID);
        lottoInfo.members[newID] = address(msg.sender);
        lottoInfo.ticketsOfMember[newID] = numTickets;

        // insert blank ticket into lottery address
        lastID = lottoInfo.ids[lottoInfo.ids.length - 1];
        uint16 blank_newID = lastID + lottoInfo.ticketsOfMember[lastID];
        
        lottoInfo.ids.push(blank_newID);
        lottoInfo.members[blank_newID] = address(this);
        lottoInfo.ticketsOfMember[blank_newID] = _numberOfTickets;

        emit BuyTicket(msg.sender, _lotteryType, _lotteryID, block.timestamp, newID, numTickets);
    }
    
    // Generate random number base on seed and timestamp.
    function randomNumberGenerate(LOTTERY_TYPE _lotteryType) private view returns (uint16) {
        // random hash from seed data
        uint randomHash = uint(keccak256(abi.encodePacked(pri_seedValue, pri_seedString, pri_seedAddress, 
                                        block.timestamp, block.difficulty, block.number)));

        Lottery_Info storage lottoInfo;
        if (_lotteryType == LOTTERY_TYPE.LOTTERY_WEEKLY) {
            lottoInfo = allWeeklyLotteryInfos[weeklyLotteryCounter - 1];
        }
        else {
            lottoInfo = allBiDailyLotteryInfos[biDailyLotteryCounter - 1];
        }
        require(lottoInfo.lotteryStatus == LOTTERY_STATUS.LOTTERY_CLOSED, "Lottery doesn't close.");

        // generate random number
        uint16 lastID = uint16(lottoInfo.ids.length - 1);
        uint16 totalMembers = lottoInfo.ids[lastID] + lottoInfo.ticketsOfMember[lottoInfo.ids[lastID]] - 1;
        uint256 maxValue = MAX_UINT_VALUE / totalMembers;
        uint16 randomNum = uint16(randomHash / maxValue) + 1;
        if (randomNum > totalMembers) {
            randomNum = 1;
        }

        return randomNum;
    }

    // only user can change seed data
    function updateSeeds(uint256 _seedValue, string memory _seedString, address _seedAddress ) external onlyOwner returns(bool) {
        // seed value check
        require(_seedValue != 0 && _seedValue != pri_seedValue, 
            "The seed value can't be 0 value and can't be the same as the previous one.");

        // seed address check
        require(_seedAddress != address(0) && _seedAddress != pri_seedAddress, 
            "The seed Address can't be 0 Address and can't be the same as the previous one.");

        // seed string check
        require(keccak256(abi.encodePacked(_seedString)) != 0 && 
            keccak256(abi.encodePacked(_seedString)) != keccak256(abi.encodePacked(pri_seedString)), 
            "The seed String can't be 0 String and can't be the same as the previous one.");

        emit LogAllSeedValueChanged(msg.sender, block.timestamp, _seedValue, _seedString, _seedAddress);

        pri_seedValue = _seedValue;
        pri_seedString = _seedString;
        pri_seedAddress = _seedAddress;

        return true;
    }

    // get winnder id
    function selectWinner(LOTTERY_TYPE _lotteryType, uint256 _lotteryID) external nonReentrantSelectWinner onlyOwner returns(uint16) {
        Lottery_Info storage lottoInfo;
        if (_lotteryType == LOTTERY_TYPE.LOTTERY_WEEKLY) {
            require(_lotteryID < weeklyLotteryCounter, "This lotteryID does not exist.");
            lottoInfo = allWeeklyLotteryInfos[_lotteryID];
        }
        else {
            require(_lotteryID < biDailyLotteryCounter, "This lotteryID does not exist.");
            lottoInfo = allBiDailyLotteryInfos[_lotteryID];
        }
        require(lottoInfo.lotteryStatus == LOTTERY_STATUS.LOTTERY_CLOSED, "This lotteryID does not close.");
        require(lottoInfo.ids.length > 1, "user does not exist");
        require(lottoInfo.poolAmount > 1, "Lottery Pool is empty!");
        
        uint16 winnerIDKey = randomNumberGenerate(_lotteryType);

        // binary search
        /* initialize variables:
            low : index of smallest value in current subarray of id array
            high: index of largest value in current subarray of id array
            mid : average of low and high in current subarray of id array */
        uint256 mid;

        uint256 low = 1;         // set initial value for low
        uint256 high = lottoInfo.ids.length - 1;  // set initial value for high

        /* perform binary search */
        while (low <= high) {
            mid = low + (high - low)/2; // update mid
            
            if ((winnerIDKey >= lottoInfo.ids[mid]) && 
                (winnerIDKey < lottoInfo.ids[mid] + lottoInfo.ticketsOfMember[lottoInfo.ids[mid]])) {
                break; // find winnerID
            }
            else if (lottoInfo.ids[mid] > winnerIDKey) { // search left subarray for val
                high = mid - 1;  // update high
            }
            else if (lottoInfo.ids[mid] < winnerIDKey) { // search right subarray for val
                low = mid + 1;        // update low
            }
        }

        // send prize AVAX to winner
        address winnerAddress = lottoInfo.members[lottoInfo.ids[mid]];
        uint256 winnerPrize = lottoInfo.poolAmount * (10 - LOTTERY_FEE) / 10;
        uint256 feePrize = lottoInfo.poolAmount * LOTTERY_FEE / 10;
        if (winnerAddress != address(this)) {
            payable(winnerAddress).transfer(winnerPrize);
            _teamFundsWallet.transfer(feePrize);
            lottoInfo.winnerPrize = winnerPrize;
            lottoInfo.poolAmount = 0;
            totalMarketcap = totalMarketcap + winnerPrize;
        }
        lottoInfo.lotteryStatus = LOTTERY_STATUS.LOTTERY_PICKED;

        emit SelectWinner(_lotteryType, _lotteryID, lottoInfo.lotteryTimeStamp, winnerAddress, winnerIDKey, winnerPrize);
        return lottoInfo.winnerID;
    }

    // get current lottery status of _lotteryID
    function getLotteryStatus(LOTTERY_TYPE _lotteryType, uint256 _lotteryID) external view returns(Ret_Ticket_Status memory) {
        Ret_Ticket_Status memory ret_ticket;
        Lottery_Info storage lottoInfo;
        if (_lotteryType == LOTTERY_TYPE.LOTTERY_WEEKLY) {
            require(_lotteryID < weeklyLotteryCounter, "This lotteryID does not exist.");
            lottoInfo = allWeeklyLotteryInfos[_lotteryID];
            ret_ticket.status = allWeeklyLotteryInfos[_lotteryID].lotteryStatus;
            ret_ticket.poolAmount = allWeeklyLotteryInfos[_lotteryID].poolAmount;
        }
        else {
            require(_lotteryID < biDailyLotteryCounter, "This lotteryID does not exist.");
            lottoInfo = allBiDailyLotteryInfos[_lotteryID];
            ret_ticket.status = allBiDailyLotteryInfos[_lotteryID].lotteryStatus;
            ret_ticket.poolAmount = allBiDailyLotteryInfos[_lotteryID].poolAmount;
        }
        uint16 lastID = lottoInfo.ids[lottoInfo.ids.length - 1];
        ret_ticket.totalCount = lastID + lottoInfo.ticketsOfMember[lastID];

        return ret_ticket;
    }
}