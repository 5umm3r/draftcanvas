import Foundation

extension ProjectStore {
    struct Snapshot: Codable {
        var projects: [Project] = []
        var items: [ProjectItem] = []
        var filteringProjects: [FilteringProject] = []
        var sidebarSelection: SidebarSelection = .none
        var expandedSections: [String: Bool] = [:]

        enum CodingKeys: String, CodingKey {
            case projects, items, filteringProjects
            case sidebarSelection, expandedSections
            case selectedProjectID, selectedFilteringProjectID
        }

        init(projects: [Project] = [], items: [ProjectItem] = [], filteringProjects: [FilteringProject] = [], sidebarSelection: SidebarSelection = .none, expandedSections: [String: Bool] = [:]) {
            self.projects = projects
            self.items = items
            self.filteringProjects = filteringProjects
            self.sidebarSelection = sidebarSelection
            self.expandedSections = expandedSections
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            projects = try c.decodeIfPresent([Project].self, forKey: .projects) ?? []
            items = try c.decodeIfPresent([ProjectItem].self, forKey: .items) ?? []
            filteringProjects = try c.decodeIfPresent([FilteringProject].self, forKey: .filteringProjects) ?? []
            expandedSections = try c.decodeIfPresent([String: Bool].self, forKey: .expandedSections) ?? [:]
            if let sel = try c.decodeIfPresent(SidebarSelection.self, forKey: .sidebarSelection) {
                sidebarSelection = sel
            } else if let filteringID = try c.decodeIfPresent(UUID.self, forKey: .selectedFilteringProjectID) {
                sidebarSelection = .filtering(filteringID)
            } else if let projectID = try c.decodeIfPresent(UUID.self, forKey: .selectedProjectID) {
                sidebarSelection = .project(projectID)
            } else {
                sidebarSelection = .none
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(projects, forKey: .projects)
            try c.encode(items, forKey: .items)
            try c.encode(filteringProjects, forKey: .filteringProjects)
            try c.encode(sidebarSelection, forKey: .sidebarSelection)
            try c.encode(expandedSections, forKey: .expandedSections)
        }
    }
}
