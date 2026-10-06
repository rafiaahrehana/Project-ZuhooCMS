package com.zuhoocms.auth.user;

import com.zuhoocms.modules.company.Company;
import com.zuhoocms.modules.company.CompanyRepository;
import com.zuhoocms.auth.role.service.AuthorizationService;
import com.zuhoocms.shared.address.Address;
import com.zuhoocms.shared.address.AddressMapper;
import com.zuhoocms.shared.address.AddressRequest;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import com.zuhoocms.shared.exception.UnauthorizedException;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import com.zuhoocms.modules.hrm.employee.EmployeeRepository;
import java.util.List;


@RestController
@RequestMapping("/api/users")
@RequiredArgsConstructor
public class UserProfileController {

    private final SecurityUtil securityUtil;
    private final UserRepository userRepository;
    private final AddressMapper addressMapper;
    private final AuthorizationService authorizationService;
    private final CompanyRepository companyRepository;
    private final EmployeeRepository employeeRepository;
    private final PasswordEncoder passwordEncoder;

    /** Resolved permission set driving frontend UI only - a UX convenience; every endpoint still enforces its own permission check server-side regardless of what this returns. */
    @GetMapping("/permissions")
    public ResponseEntity<List<String>> getMyPermissions() {
        return ResponseEntity.ok(authorizationService.getMyPermissionCodes());
    }

    @GetMapping("/profile")
    @Transactional(readOnly = true)
    public ResponseEntity<UserProfileResponse> getProfile() {
        User principal = securityUtil.getCurrentUser();
        if (principal == null) {
            throw new UnauthorizedException("User not authenticated");
        }

        User user = userRepository.findById(principal.getId())
                .orElseThrow(() -> new ResourceNotFoundException("User not found"));

        return ResponseEntity.ok(mapToResponse(user));
    }

    @PatchMapping("/profile")
    @Transactional
    public ResponseEntity<UserProfileResponse> updateProfile(@Valid @RequestBody UserProfileRequest request) {
        User principal = securityUtil.getCurrentUser();
        if (principal == null) {
            throw new UnauthorizedException("User not authenticated");
        }

        User user = userRepository.findById(principal.getId())
                .orElseThrow(() -> new ResourceNotFoundException("User not found"));

        if (request.getFirstName() != null) {
            user.setFirstName(request.getFirstName().trim());
        }
        if (request.getLastName() != null) {
            user.setLastName(request.getLastName().trim());
        }
        if (request.getEmail() != null && !request.getEmail().isBlank()) {
            String newEmail = request.getEmail().trim().toLowerCase();
            if (!newEmail.equalsIgnoreCase(user.getEmail())) {
                if (request.getCurrentPassword() == null || request.getCurrentPassword().isBlank()) {
                    throw new BadRequestException("Enter your current password to change your email.");
                }
                if (!passwordEncoder.matches(request.getCurrentPassword(), user.getPassword())) {
                    throw new BadRequestException("Current password is incorrect.");
                }
                if (userRepository.existsByEmail(newEmail)) {
                    throw new BadRequestException("An account with this email already exists.");
                }
                user.setEmail(newEmail);
            }
        }
        if (request.getPhone() != null) {
            user.setPhone(request.getPhone().trim());
        }
        if (request.getImage() != null) {
            user.setImage(com.zuhoocms.shared.storage.FileReferencePolicy.requireOwn(request.getImage().trim(), user.getImage()));
        }
        if (request.getLanguagePreference() != null) {
            user.setLanguagePreference(request.getLanguagePreference().trim());
        }

        if (request.getLocation() != null) {
            AddressRequest locReq = request.getLocation();
            if (user.getLocation() == null) {
                Address newLoc = addressMapper.toEntity(locReq);
                user.setLocation(newLoc);
            } else {
                addressMapper.updateEntityFromRequest(user.getLocation(), locReq);
            }
        }

        Long companyId = securityUtil.getCurrentCompanyId();
        if (companyId != null && request.getCompanyEmail() != null) {
            Company company = companyRepository.findById(companyId)
                    .orElseThrow(() -> new ResourceNotFoundException("Company not found"));
            company.setCompanyEmail(request.getCompanyEmail().trim());
            companyRepository.save(company);
        }

        User savedUser = userRepository.save(user);
        return ResponseEntity.ok(mapToResponse(savedUser));
    }

    private UserProfileResponse mapToResponse(User user) {
        String companyEmail = null;
        Long companyId = securityUtil.getCurrentCompanyId();
        if (companyId != null) {
            companyEmail = companyRepository.findById(companyId)
                    .map(Company::getCompanyEmail)
                    .orElse(null);
        }
        // Falls back to the employee profileImageUrl for employees created before the two fields were kept in sync.
        String imageUrl = user.getImage();
        if ((imageUrl == null || imageUrl.isBlank()) && companyId != null) {
            imageUrl = employeeRepository.findByUserIdAndCompanyId(user.getId(), companyId)
                    .map(emp -> emp.getProfileImageUrl())
                    .orElse(null);
        }
        return UserProfileResponse.builder()
                .id(user.getId())
                .firstName(user.getFirstName())
                .lastName(user.getLastName())
                .email(user.getEmail())
                .phone(user.getPhone())
                .image(imageUrl)
                .role(user.getRole())
                .languagePreference(user.getLanguagePreference())
                .location(addressMapper.toResponse(user.getLocation()))
                .companyEmail(companyEmail)
                .build();
    }
}
