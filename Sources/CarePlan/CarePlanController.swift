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
	
	public let plan: CarePlan
	
	
	public init(plan: CarePlan) {
		self.plan = plan
	}
	
	
	// Accessing individual parts of the plan
	
	public func subjectOrGroup(callback: ((patient: Patient?, group: Group?, reference: Reference?) -> Void)) {
		guard let subject = plan.subject else {
			callback(patient: nil, group: nil, reference: nil)
			return
		}
		subject.resolve(Resource.self) { subject in
			dispatch_async(dispatch_get_main_queue()) {
				let patient = subject as? Patient
				let group = subject as? Group
				callback(patient: patient, group: group, reference: self.plan.subject)
			}
		}
	}
	
	public func planParticipants(callback: ((participants: [OCKContact]?) -> Void)) {
		guard let participants = plan.participant where participants.count > 0 else {
			callback(participants: nil)
			return
		}
		
		var list = [OCKContact]()
		var idx = 0
		
		// loop all participants and resolve, if necessary
		let group = dispatch_group_create()
		for participant in participants {
			if let member = participant.member {
				dispatch_group_enter(group)
				member.resolve(Resource.self) { resource in
					var role = participant.role?.text ?? participant.role?.coding?[0].code
					var name: String?
					var monogram: String?
					var phone: String?
					var email: String?
					var color: UIColor?
					var image: UIImage?
					
					if let practitioner = resource as? Practitioner {
						role = "Practitioner"
						name = HumanName.c3_humanName(practitioner.name) ?? "Unnamed Practitioner"
						monogram = HumanName.c3_monogram(practitioner.name) ?? "PR"
						phone = ContactPoint.c3_phone(practitioner.telecom)
						email = ContactPoint.c3_email(practitioner.telecom)
						color = UIColor.orangeColor()
						image = nil
					}
					else if let person = resource as? RelatedPerson {
						name = HumanName.c3_humanName(person.name) ?? "Unnamed Person"
						monogram = HumanName.c3_monogram(person.name) ?? "PE"
						phone = ContactPoint.c3_phone(person.telecom)
						email = ContactPoint.c3_email(person.telecom)
						color = UIColor.redColor()
					}
					else if let patient = resource as? Patient {
						name = HumanName.c3_humanName(patient.name) ?? "Unnamed Patient"
						monogram = HumanName.c3_monogram(patient.name) ?? "PA"
						phone = ContactPoint.c3_phone(patient.telecom)
						email = ContactPoint.c3_email(patient.telecom)
						color = UIColor.greenColor()
					}
					else if let organization = resource as? Organization {
						name = organization.name ?? "Unnamed Organization"
						monogram = "ORG"
						phone = ContactPoint.c3_phone(organization.telecom)
						email = ContactPoint.c3_email(organization.telecom)
					}
					
					let contact = OCKContact(contactType: OCKContactType.CareTeam,
					                         name: name ?? "Unnamed Participant",
					                         relation: role ?? "Participant",
					                         tintColor: color,
					                         phoneNumber: (nil != phone) ? CNPhoneNumber(stringValue: phone!) : nil,
					                         messageNumber: nil,
					                         emailAddress: email,
					                         monogram: monogram ?? "PT",
					                         image: image)
					list.insert(contact, atIndex: min(idx, list.count))
					dispatch_group_leave(group)
				}
			}
			else {
				fhir_warn("Participant \(participant) does not have a member")
			}
			idx += 1
		}
		
		dispatch_group_notify(group, dispatch_get_main_queue()) {
			callback(participants: list)
		}
	}
	
	public func activities(callback: ((activities: [OCKCarePlanActivity]?) -> Void)) {
		guard let activities = plan.activity where activities.count > 0 else {
			callback(activities: nil)
			return
		}
		
		var list = [OCKCarePlanActivity]()
		var idx = 0
		
		// loop all activity details and references
		let group = dispatch_group_create()
		for activity in activities {
			if let reference = activity.reference {
				dispatch_group_enter(group)
				
				// resolved activity reference
				reference.resolve(Resource.self) { resource in
					var title = "Referenced Activity"
					var text: String?
					var instructions: String?
					
					// inspect all possible resource types
					if let order = resource as? DiagnosticOrder {
						if let item = order.item?.first {
							// TODO: support more that one item
							var coding = item.code?.coding?.first
							if let codes = item.code?.coding {
								for code in codes {
									if "http://loinc.org" == code.system {
										coding = code
										break
									}
								}
							}
							title = coding?.display ?? coding?.code ?? title
						}
						else {
							NSLog("WARNING: the diagnostic order \(order) does not have a single item")
						}
						text = "This is a text"
						instructions = "These are our instructions"
					}
					else {
						// TODO: add more resource types
						NSLog("Unsupported activity resource: \(resource)")
					}
					
					let components = NSCalendar.currentCalendar().componentsInTimeZone(NSTimeZone.localTimeZone(), fromDate: NSDate())
					let schedule = OCKCareSchedule.dailyScheduleWithStartDate(components, occurrencesPerDay: 1)
					
					let activity = OCKCarePlanActivity.interventionWithIdentifier(
						resource?.id ?? "unidentified-activity",
						groupIdentifier: nil,
						title: title,
						text: text,
						tintColor: nil,
						instructions: instructions,
						imageURL: nil,
						schedule: schedule,
						userInfo: nil)
					list.insert(activity, atIndex: min(idx, list.count))
					dispatch_group_leave(group)
				}
			}
			
			// activity detail
			else if let detail = activity.detail {
				var title = "Detail Activity"
				var text: String?
				var instructions: String?
				
				let components = NSCalendar.currentCalendar().componentsInTimeZone(NSTimeZone.localTimeZone(), fromDate: NSDate())
				let schedule = OCKCareSchedule.dailyScheduleWithStartDate(components, occurrencesPerDay: 1)
				
				let activity = OCKCarePlanActivity.interventionWithIdentifier(
					"detail-\(idx)",
					groupIdentifier: nil,
					title: title,
					text: text,
					tintColor: nil,
					instructions: instructions,
					imageURL: nil,
					schedule: schedule,
					userInfo: nil)
				list.insert(activity, atIndex: min(idx, list.count))
			}
			else {
				fhir_warn("CarePlan activity \(activity) does neither have a reference nor detail")
			}
			idx += 1
		}
		
		// all resolved
		dispatch_group_notify(group, dispatch_get_main_queue()) {
			callback(activities: list)
		}
	}
	
	public func activityWithId(id: String) -> (CarePlanActivity, Resource?)? {
		guard let activities = plan.activity else {
			return nil
		}
		
		var idx = 0
		for activity in activities {
			if let _ = activity.detail {
				if "detail-\(idx)" == id {
					return (activity, nil)
				}
			}
			else if let resource = activity.reference?.resolved(Resource.self) {
				if id == resource.id {
					return (activity, resource)
				}
			}
			else {
				NSLog("Unresolved reference in activity: \(activity.reference?.description ?? "nil")")
			}
			idx += 1
		}
		return nil;
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
		name.given?.forEach() {
			if $0.characters.count > 0 {
				initials.append($0[$0.startIndex..<$0.startIndex.advancedBy(1)])
			}
		}
		name.family?.forEach() {
			if $0.characters.count > 0 {
				initials.append($0[$0.startIndex..<$0.startIndex.advancedBy(1)])
			}
		}
		
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

