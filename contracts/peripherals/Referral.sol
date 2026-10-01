// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./interfaces/IReferral.sol";

import "../AuthorityUtil.sol";
import "../proxy/OwnableUpgradeable.sol";

contract Referral is IReferral, OwnableUpgradeable, AuthorityUtil {
    mapping(address => address) public parent;
    mapping(address => address) public grandParent;
    mapping(address => uint256) public childrenCount;

    uint256 public referralDiscountRate; // default 1000 => 10%

    mapping(address => bool) public affiliates;
    mapping(address => uint256) public affiliatesDiscountRate;

    uint256 public referralFeeRebateRate;
    mapping(address => uint256) public affiliatesFeeRebateRate;

    mapping(address => bool) public partners;
    mapping(address => uint256) public partnersDiscountRate;
    mapping(address => uint256) public partnersTerm; // timestamp in seconds

    event ParentChanged(
        address indexed user,
        address indexed parent,
        address indexed grandParent
    );
    event SetReferralRate(uint256 discountRate, uint256 feeRebateRate);
    event AddedToAffiliates(
        address indexed account,
        uint256 discountRate,
        uint256 feeRebateRate
    );
    event RemovedFromAffiliates(address indexed account);
    event SetPartner(
        address indexed account,
        bool isPartner,
        uint256 discountRate,
        uint256 term
    );

    function initialize(IOptionsAuthority _authority) external initializer {
        __Ownable_init();
        __AuthorityUtil_init__(_authority);
    }

    function setParent(address _parent) public {
        _setParent(msg.sender, _parent, parent[_parent]);
        emit ParentChanged(msg.sender, _parent, parent[_parent]);
    }

    function setParentAdmin(
        address[] memory _children,
        address[] memory _parents,
        address[] memory _grandParents
    ) public onlyAdmin {
        require(
            _children.length == _parents.length &&
                _children.length == _grandParents.length,
            "Referral: mismatch length"
        );

        for (uint256 i = 0; i < _children.length; i++) {
            _setParent(_children[i], _parents[i], _grandParents[i]);
        }
    }

    function _setParent(
        address _child,
        address _parent,
        address _grandParent
    ) private {
        require(
            _child != address(0) && _parent != address(0),
            "Referral: cannot set zero address"
        );

        require(
            _child != _parent && _child != _grandParent,
            "Referral: inappropriate relationship"
        );

        address currParent = parent[_child];
        require(currParent == address(0), "Referral: already set as parent");

        parent[_child] = _parent;
        grandParent[_child] = _grandParent;
        childrenCount[_parent] += 1;
    }

    function getParentInfo(
        address _user
    ) public view returns (address, address) {
        return (parent[_user], grandParent[_user]);
    }

    function setReferralRate(
        uint256 _discountRate,
        uint256 _feeRebateRate
    ) public override onlyAdmin {
        require(
            _discountRate <= 10000,
            "Referral: cannot set discount rate over 100%"
        );
        require(
            _feeRebateRate <= 10000,
            "Referral: cannot set fee rebate rate over 100%"
        );

        referralDiscountRate = _discountRate;
        referralFeeRebateRate = _feeRebateRate;

        emit SetReferralRate(_discountRate, _feeRebateRate);
    }

    function addToAffiliates(
        address _account,
        uint256 _discountRate,
        uint256 _feeRebateRate
    ) public override onlyAdmin returns (bool) {
        require(
            _account != address(0),
            "Referral: cannot add zero addres to affiliates"
        );
        require(
            _discountRate <= 10000,
            "Referral: cannot set discount rate over 100%"
        );
        require(
            _feeRebateRate <= 10000,
            "Referral: cannot set fee rebate rate over 100%"
        );

        affiliates[_account] = true;
        affiliatesDiscountRate[_account] = _discountRate;
        affiliatesFeeRebateRate[_account] = _feeRebateRate;

        emit AddedToAffiliates(_account, _discountRate, _feeRebateRate);

        return true;
    }

    function removeFromAffiliates(
        address _account
    ) public override onlyAdmin returns (bool) {
        require(
            _account != address(0),
            "Referral: cannot remove zero addres from affiliates"
        );

        delete affiliates[_account];
        delete affiliatesDiscountRate[_account];
        delete affiliatesFeeRebateRate[_account];

        emit RemovedFromAffiliates(_account);

        return true;
    }

    function addToAffiliatesInBatch(
        address[] memory _accounts,
        uint256[] memory _discountRates,
        uint256[] memory _feeRebateRate
    ) public override {
        require(
            _accounts.length == _discountRates.length &&
                _accounts.length == _feeRebateRate.length,
            "Referral: mismatch length"
        );

        for (uint256 i = 0; i < _accounts.length; i++) {
            addToAffiliates(_accounts[i], _discountRates[i], _feeRebateRate[i]);
        }
    }

    function removeFromAffiliatesInBatch(
        address[] memory _accounts
    ) public override {
        for (uint256 i = 0; i < _accounts.length; i++) {
            removeFromAffiliates(_accounts[i]);
        }
    }

    function isAffiliates(
        address _account
    ) public view override returns (bool) {
        require(_account != address(0), "Referral: cannot check zero address");
        return affiliates[_account];
    }

    function setPartner(
        address _account,
        bool _isPartner,
        uint256 _discountRate,
        uint256 _term
    ) public override onlyAdmin {
        require(
            _account != address(0),
            "Referral: cannot add zero addres to partners"
        );

        if (!_isPartner) {
            delete partners[_account];
            delete partnersDiscountRate[_account];
            delete partnersTerm[_account];

            emit SetPartner(_account, _isPartner, 0, 0);
            return;
        }

        require(
            _discountRate <= 10000,
            "Referral: cannot set discount rate over 100%"
        );
        require(
            _term > block.timestamp,
            "Referral: cannot set term in the past"
        );

        partners[_account] = _isPartner;
        partnersDiscountRate[_account] = _discountRate;
        partnersTerm[_account] = _term;

        emit SetPartner(_account, _isPartner, _discountRate, _term);
    }

    /*
     * @dev Get rate info for _account
     * @param _account The account to get rate info
     * @return discount rate, parent address, fee rebate rate
     */
    function getRateInfo(
        address _account
    ) public view returns (uint256, address, uint256) {
        require(
            _account != address(0),
            "Referral: cannot get rate from zero address"
        );

        uint256 currentTime = block.timestamp;

        // Check whether _account is partner
        if (partners[_account] && partnersTerm[_account] > currentTime) {
            return (partnersDiscountRate[_account], address(0), 0);
        }

        // Check whether _account has a parent, and if so, whether the parent is an affiliate
        address _parent = parent[_account];

        if (_parent != address(0)) {
            if (isAffiliates(_parent)) {
                return (
                    affiliatesDiscountRate[_parent],
                    _parent,
                    affiliatesFeeRebateRate[_parent]
                );
            }

            return (referralDiscountRate, _parent, referralFeeRebateRate);
        }

        return (0, address(0), 0);
    }

    receive() external payable {}
}
