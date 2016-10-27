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


open class CarePlanController {
	
	public let plan: CarePlan
	
	
	public init(plan: CarePlan) {
		self.plan = plan
	}
	
	
	// Accessing individual parts of the plan
	
	open func subjectOrGroup(_ callback: @escaping ((_ patient: Patient?, _ group: Group?, _ reference: Reference?) -> Void)) {
		guard let subject = plan.subject else {
			callback(nil, nil, nil)
			return
		}
		subject.resolve(Resource.self) { subject in
			DispatchQueue.main.async() {
				let patient = subject as? Patient
				let group = subject as? Group
				callback(patient, group, self.plan.subject)
			}
		}
	}
	
	open func planParticipants(_ callback: @escaping ((_ participants: [OCKContact]?) -> Void)) {
		guard let participants = plan.participant , participants.count > 0 else {
			callback(nil)
			return
		}
		
		var list = [OCKContact]()
		var idx = 0
		
		// loop all participants and resolve, if necessary
		let group = DispatchGroup()
		for participant in participants {
			if let member = participant.member {
				group.enter()
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
						color = UIColor.orange
						image = nil
					}
					else if let person = resource as? RelatedPerson {
						name = HumanName.c3_humanName(person.name) ?? "Unnamed Person"
						monogram = HumanName.c3_monogram(person.name) ?? "PE"
						phone = ContactPoint.c3_phone(person.telecom)
						email = ContactPoint.c3_email(person.telecom)
						color = UIColor.red
					}
					else if let patient = resource as? Patient {
						name = HumanName.c3_humanName(patient.name) ?? "Unnamed Patient"
						monogram = HumanName.c3_monogram(patient.name) ?? "PA"
						phone = ContactPoint.c3_phone(patient.telecom)
						email = ContactPoint.c3_email(patient.telecom)
						color = UIColor.green
					}
					else if let organization = resource as? Organization {
						name = organization.name ?? "Unnamed Organization"
						monogram = "ORG"
						phone = ContactPoint.c3_phone(organization.telecom)
						email = ContactPoint.c3_email(organization.telecom)
					}
					
					let contact = OCKContact(contactType: OCKContactType.careTeam,
					                         name: name ?? "Unnamed Participant",
					                         relation: role ?? "Participant",
					                         tintColor: color,
					                         phoneNumber: (nil != phone) ? CNPhoneNumber(stringValue: phone!) : nil,
					                         messageNumber: nil,
					                         emailAddress: email,
					                         monogram: monogram ?? "PT",
					                         image: image)
					list.insert(contact, at: min(idx, list.count))
					group.leave()
				}
			}
			else {
				fhir_warn("Participant \(participant) does not have a member")
			}
			idx += 1
		}
		
		group.notify(queue: DispatchQueue.main) {
			callback(list)
		}
	}
	
	open func activities(_ callback: @escaping ((_ activities: [OCKCarePlanActivity]?) -> Void)) {
		guard let activities = plan.activity , activities.count > 0 else {
			callback(nil)
			return
		}
		
		var list = [OCKCarePlanActivity]()
		var idx = 0
		
		// loop all activity details and references
		let group = DispatchGroup()
		for activity in activities {
			if let reference = activity.reference {
				group.enter()
				
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
									if "http://loinc.org" == code.system?.absoluteString ?? "x" {
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
					
					let components = Calendar.current.dateComponents(in: TimeZone.current, from: Date())
					let schedule = OCKCareSchedule.dailySchedule(withStartDate: components, occurrencesPerDay: 1)
					
					let activity = OCKCarePlanActivity.intervention(
						withIdentifier: resource?.id ?? "unidentified-activity",
						groupIdentifier: nil,
						title: title,
						text: text,
						tintColor: nil,
						instructions: instructions,
						imageURL: nil,
						schedule: schedule,
						userInfo: nil)
					list.insert(activity, at: min(idx, list.count))
					group.leave()
				}
			}
			
			// activity detail
			else if let detail = activity.detail {
				var title = "Detail Activity"
				var text: String?
				var instructions: String?
				
				let components = Calendar.current.dateComponents(in: TimeZone.current, from: Date())
				let schedule = OCKCareSchedule.dailySchedule(withStartDate: components, occurrencesPerDay: 1)
				
				let activity = OCKCarePlanActivity.intervention(
					withIdentifier: "detail-\(idx)",
					groupIdentifier: nil,
					title: title,
					text: text,
					tintColor: nil,
					instructions: instructions,
					imageURL: nil,
					schedule: schedule,
					userInfo: nil)
				list.insert(activity, at: min(idx, list.count))
			}
			else {
				fhir_warn("CarePlan activity \(activity) does neither have a reference nor detail")
			}
			idx += 1
		}
		
		// all resolved
		group.notify(queue: DispatchQueue.main) {
			callback(list)
		}
	}
	
	open func activityWithId(_ id: String) -> (CarePlanActivity, Resource?)? {
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
	
	public class func c3_humanName(_ names: [HumanName]?) -> String? {
		guard let names = names , names.count > 0 else {
			return nil
		}
		
		var nms = [String]()
		for name in names {
			if let name = self.c3_humanName(name) {
				nms.append(name)
			}
		}
		return (nms.count > 0) ? nms.joined(separator: ", ") : nil
	}
	
	public class func c3_humanName(_ name: HumanName?) -> String? {
		guard let name = name else {
			return nil
		}
		
		var nm = [String]()
		name.prefix?.forEach() { nm.append($0) }
		name.given?.forEach() { nm.append($0) }
		name.family?.forEach() { nm.append($0) }
		name.suffix?.forEach() { nm.append($0) }
		
		return (nm.count > 0) ? nm.joined(separator: " ") : name.text
	}
	
	public class func c3_monogram(_ names: [HumanName]?) -> String? {
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
	
	public class func c3_monogram(_ name: HumanName?) -> String? {
		guard let name = name else {
			return nil
		}
		
		var initials = [String]()
		name.given?.forEach() {
			if $0.characters.count > 0 {
				initials.append("\($0.characters.first)")
			}
		}
		name.family?.forEach() {
			if $0.characters.count > 0 {
				initials.append("\($0.characters.first)")
			}
		}
		
		return (initials.count > 0) ? initials.joined(separator: "") : nil;
	}
}


extension ContactPoint {
	
	public class func c3_phone(_ contacts: [ContactPoint]?, use: String? = nil) -> String? {
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
	
	public class func c3_email(_ contacts: [ContactPoint]?, use: String? = nil) -> String? {
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

