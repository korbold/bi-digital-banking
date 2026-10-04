import 'package:feature_auth/feature_auth.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockCustomerRepository extends Mock implements CustomerRepository {}

const user = AuthUser(uid: 'u1', email: 'ana@test.com');
const customer = Customer(uid: 'u1', name: 'Ana López', segment: 'retail');
