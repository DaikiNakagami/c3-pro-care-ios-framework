//
//  CarePlanController.swift
//  C3PROCare
//
//  Created by Pascal Pfiffner on 05/05/16.
//  Copyright © 2016 Boston Children's Hospital. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation
import SMART
import CareKit


public class CarePlanController {
	
	public let carePlan: CarePlan
	
	
	public init(plan: CarePlan) {
		carePlan = plan
	}
	
	
	// Accessing individual parts of the plan
	
	public func subjectOrGroup(callback: ((patient: Patient?, group: Group?, reference: Reference?) -> Void)) {
		guard let subject = carePlan.subject else {
			callback(patient: nil, group: nil, reference: nil)
			return
		}
		subject.resolve(Resource.self) { subject in
			let patient = subject as? Patient
			let group = subject as? Group
			callback(patient: patient, group: group, reference: self.carePlan.subject)
		}
	}
	
	public func planParticipants(callback: ((participants: [OCKContact]?) -> Void)) {
		guard let participants = carePlan.participant where participants.count > 0 else {
			callback(participants: nil)
			return
		}
		
		// resolve all participant references
		let group = dispatch_group_create()
		participants.forEach() {
			if let member = $0.member {
				dispatch_group_enter(group)
				member.resolve(Resource.self) { resource in
					dispatch_group_leave(group)
				}
			}
		}
		
		// all resolved
		dispatch_group_notify(group, dispatch_get_main_queue()) {
			var list = [OCKContact]()
			for participant in participants {
				let role = participant.role?.text ?? participant.role?.coding?[0].code
				var name: String?
				var phone: String?
				var email: String?
				var monogram: String?
				var image: UIImage?
				
				if let practitioner = participant.member?.resolved(Practitioner.self) {
					name = HumanName.c3_humanName(practitioner.name) ?? "Unnamed Practitioner"
					monogram = HumanName.c3_monogram(practitioner.name) ?? "PR"
					phone = ContactPoint.c3_phone(practitioner.telecom)
					email = ContactPoint.c3_phone(practitioner.telecom)
				}
				else if let person = participant.member?.resolved(RelatedPerson.self) {
					name = HumanName.c3_humanName(person.name) ?? "Unnamed Person"
					monogram = HumanName.c3_monogram(person.name) ?? "PE"
					phone = ContactPoint.c3_phone(person.telecom)
					email = ContactPoint.c3_phone(person.telecom)
				}
				else if let patient = participant.member?.resolved(Patient.self) {
					name = HumanName.c3_humanName(patient.name) ?? "Unnamed Patient"
					monogram = HumanName.c3_monogram(patient.name) ?? "PA"
					phone = ContactPoint.c3_phone(patient.telecom)
					email = ContactPoint.c3_phone(patient.telecom)
				}
				else if let organization = participant.member?.resolved(Organization.self) {
					name = organization.name ?? "Unnamed Organization"
					monogram = "ORG"
					phone = ContactPoint.c3_phone(organization.telecom)
					email = ContactPoint.c3_phone(organization.telecom)
				}
				
				let contact = OCKContact(contactType: OCKContactType.CareTeam,
				                         name: name ?? "Unnamed Participant",
				                         relation: role ?? "Participant",
				                         tintColor: nil,
				                         phoneNumber: (nil != phone) ? CNPhoneNumber(stringValue: phone!) : nil,
				                         messageNumber: nil,
				                         emailAddress: email,
				                         monogram: monogram ?? "PT",
				                         image: image)
				list.append(contact)
			}
			callback(participants: list)
		}
	}
}


extension HumanName {
	
	public class func c3_humanName(names: [HumanName]?) -> String? {
		guard let names = names where names.count > 0 else {
			return nil
		}
		
		var nms = [String]()
		for name in names {
			if let name = self.c3_humanName(name) {
				nms.append(name)
			}
		}
		return (nms.count > 0) ? nms.joinWithSeparator(", ") : nil
	}
	
	public class func c3_humanName(name: HumanName?) -> String? {
		guard let name = name else {
			return nil
		}
		
		var nm = [String]()
		name.prefix?.forEach() { nm.append($0) }
		name.given?.forEach() { nm.append($0) }
		name.family?.forEach() { nm.append($0) }
		name.suffix?.forEach() { nm.append($0) }
		
		return (nm.count > 0) ? nm.joinWithSeparator(" ") : name.text
	}
	
	public class func c3_monogram(names: [HumanName]?) -> String? {
		guard let names = names else {
			return nil
		}
		
		for name in names {
			// check "use"?
			if let monogram = self.c3_monogram(name) {
				return monogram
			}
		}
		return nil;
	}
	
	public class func c3_monogram(name: HumanName?) -> String? {
		guard let name = name else {
			return nil
		}
		
		var initials = [String]()
		name.given?.forEach() { initials.append($0[$0.startIndex..<$0.startIndex.advancedBy(1)]) }
		name.family?.forEach() { initials.append($0[$0.startIndex..<$0.startIndex.advancedBy(1)]) }
		
		return (initials.count > 0) ? initials.joinWithSeparator("") : nil;
	}
}


extension ContactPoint {
	
	public class func c3_phone(contacts: [ContactPoint]?, use: String? = nil) -> String? {
		guard let contacts = contacts else {
			return nil
		}
		
		for contact in contacts {
			if "phone" == contact.system && (nil == use || use == contact.use) {
				return contact.value
			}
		}
		return nil
	}
	
	public class func c3_email(contacts: [ContactPoint]?, use: String? = nil) -> String? {
		guard let contacts = contacts else {
			return nil
		}
		
		for contact in contacts {
			if "email" == contact.system && (nil == use || use == contact.use) {
				return contact.value
			}
		}
		return nil
	}
}

